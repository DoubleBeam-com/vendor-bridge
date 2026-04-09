require "roo"
require_relative "registry"

module VendorBridge
  module Adapters
    class CnduitV1
      # Maps keywords found in section titles to normalized categories.
      # Checked in order — first match wins.
      SECTION_CATEGORY_KEYWORDS = [
        ["Bubblehash Infused Joints", "Infused Preroll"],
        ["Infused Joints",           "Infused Preroll"],
        ["Terp Infused Preroll",     "Infused Preroll"],
        ["Infused Preroll",          "Infused Preroll"],
        ["Infused",                  "Infused Preroll"],
        ["Flower Joints",            "Preroll"],
        ["Prerolls",                 "Preroll"],
        ["Preroll",                  "Preroll"],
        ["Flower",                   "Flower"],
        ["Disposable Vape",          "Vape"],
        ["Vape Cartridge",           "Vape"],
        ["Vape",                     "Vape"],
        ["Rosin Concentrates",       "Concentrate"],
        ["Rosin Concentrate",        "Concentrate"],
        ["BHO Concentrate",          "Concentrate"],
        ["Concentrate",              "Concentrate"],
      ].freeze

      FILL_DOWN_COLUMNS = ["Brand Name", "State", "Category"].freeze
      ARROW_PATTERN = /\A\s*\u2193\s*\z/

      def flatten(file_path)
        unless File.extname(file_path).downcase == ".xlsx"
          raise ArgumentError, "This doesn't look like a CNDUIT product library. Please upload the original .xlsx file."
        end

        begin
          xlsx = Roo::Excelx.new(file_path)
        rescue => e
          raise ArgumentError, "This doesn't look like a valid CNDUIT product library. Make sure you're uploading the original Excel file (.xlsx)."
        end

        sheet = xlsx.sheets.first
        xlsx.default_sheet = sheet

        if xlsx.last_row.nil? || xlsx.last_row < 2
          xlsx.close
          raise ArgumentError, "The sheet appears to be empty."
        end

        sections = detect_sections(xlsx)
        if sections.empty?
          xlsx.close
          raise ArgumentError, "Could not find any product sections. Expected repeated 'Product Name' header rows."
        end

        all_rows = []
        all_columns = Set.new
        stats = Hash.new { |h, k| h[k] = { total: 0, kept: 0 } }

        sections.each do |section|
          headers = read_headers(xlsx, section[:header_row])
          all_columns.merge(headers)

          anchor = {}  # fill-down values for this section

          section[:data_range].each do |row_num|
            raw = read_row(xlsx, headers, row_num)

            # Skip separator rows, empty rows, annotation rows
            product_name = raw["Product Name"]
            next if product_name.nil? || (product_name.is_a?(String) && product_name.strip.empty?)
            next if separator_row?(product_name)
            next if annotation_row?(product_name)

            # Fill-down logic
            apply_fill_down(raw, anchor)

            category = section[:category] || raw["Category"]&.to_s&.strip
            next if category.nil? || category.empty?

            stats[category][:total] += 1

            # Synthetic fields
            raw["_source_sheet"]    = section[:title]
            raw["_product_category"] = category
            raw["_source_row"]      = row_num
            raw["_section_title"]   = section[:section_label]
            raw["_cover_image_url"] = extract_image_url(raw["Image"])
            lineage = raw["Type"]&.to_s&.strip
            raw["_lineage"]         = (lineage.nil? || lineage.empty?) ? nil : lineage
            raw["_parsed_pack_size"] = section[:pack_size]

            all_rows << raw
            stats[category][:kept] += 1
          end
        end

        xlsx.close

        synthetic = %w[_source_sheet _product_category _source_row _section_title
                       _cover_image_url _lineage _parsed_pack_size]
        synthetic.each { |s| all_columns.add(s) }
        ordered_columns = synthetic + (all_columns.to_a - synthetic).sort

        { rows: all_rows, columns: ordered_columns, stats: stats }
      end

      private

      # Finds all header rows (column A == "Product Name") and builds section metadata.
      def detect_sections(xlsx)
        last_row = xlsx.last_row || 0
        header_rows = []

        (1..last_row).each do |r|
          val = xlsx.cell(r, 1)
          header_rows << r if val.is_a?(String) && val.strip == "Product Name"
        end

        sections = []
        header_rows.each_with_index do |hr, idx|
          title_row = hr - 1
          raw_title = xlsx.cell(title_row, 1)&.to_s&.strip || ""
          raw_title = raw_title.sub(/\A\*\s*/, "")  # strip leading asterisk

          section_label = parse_section_label(raw_title)
          category = resolve_category_from_title(section_label)
          pack_size = parse_pack_size(section_label)

          # Data range: from header_row+1 to just before the next separator/header
          data_start = hr + 1
          data_end = find_section_end(xlsx, data_start, header_rows[idx + 1])

          sections << {
            header_row: hr,
            title: raw_title,
            section_label: section_label,
            category: category,
            pack_size: pack_size,
            data_range: (data_start..data_end),
          }
        end

        sections
      end

      # Find the last data row before the next section starts.
      def find_section_end(xlsx, data_start, next_header_row)
        last_row = xlsx.last_row || 0
        # Stop before the next section's title row (which is at next_header - 1)
        boundary = next_header_row ? next_header_row - 2 : last_row

        # Walk backward from boundary, skipping empty and separator rows
        end_row = data_start - 1  # default: no data rows
        (data_start..boundary).each do |r|
          val = xlsx.cell(r, 1)
          next if val.nil?
          str = val.to_s.strip
          next if str.empty?
          break if str == "Product Name"  # hit next header
          next if str.start_with?("///")  # separator
          end_row = r
        end

        end_row < data_start ? data_start - 1 : end_row
      end

      # Extracts the product line portion after the brand name.
      # "MAMA J'S - Classic Prerolls - 2pk" -> "Classic Prerolls - 2pk"
      # "HUSTLER'S AMBITION - Flower" -> "Flower"
      def parse_section_label(title)
        parts = title.split(" - ", 2)
        parts.length > 1 ? parts[1].strip : title
      end

      # Maps section label keywords to a normalized category.
      def resolve_category_from_title(section_label)
        SECTION_CATEGORY_KEYWORDS.each do |keyword, category|
          return category if section_label.downcase.include?(keyword.downcase)
        end
        nil
      end

      # Parses pack size from section label: "Classic Prerolls - 2pk" -> 2
      def parse_pack_size(section_label)
        match = section_label.match(/(\d+)\s*pk\b/i)
        match ? match[1].to_i : nil
      end

      # Fill-down: set anchor values from first row, propagate to subsequent rows.
      def apply_fill_down(row, anchor)
        FILL_DOWN_COLUMNS.each do |col|
          val = row[col]
          if val.nil? || (val.is_a?(String) && (val.strip.empty? || val.match?(ARROW_PATTERN)))
            # Use anchor value
            row[col] = anchor[col]
          else
            # This is a real value — update anchor
            anchor[col] = val.is_a?(String) ? val.strip : val
            row[col] = anchor[col]
          end
        end
      end

      def separator_row?(val)
        val.is_a?(String) && val.strip.start_with?("///")
      end

      def annotation_row?(val)
        return false unless val.is_a?(String)
        stripped = val.strip.upcase
        stripped.include?("PENDING") || stripped.include?("NEW PRODUCTS") || stripped.include?("COMING SOON")
      end

      def extract_image_url(val)
        return nil if val.nil?
        str = val.to_s.strip
        str.match?(/\Ahttps?:\/\//i) ? str : nil
      end

      def read_headers(xlsx, header_row)
        raw = (1..(xlsx.last_column || 0)).map { |c| xlsx.cell(header_row, c) }
        raw.pop while raw.any? && raw.last.nil?
        raw.map { |h| h&.to_s&.strip }.compact.reject(&:empty?)
      end

      def read_row(xlsx, headers, row_num)
        row = {}
        headers.each_with_index do |header, idx|
          next if header.nil? || header.empty?
          row[header] = xlsx.cell(row_num, idx + 1)
        end
        row
      end
    end

    Registry.register_adapter("cnduit_v1", CnduitV1)
  end
end
