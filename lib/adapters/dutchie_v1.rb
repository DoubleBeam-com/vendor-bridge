require "roo"
require_relative "registry"

module VendorBridge
  module Adapters
    class DutchieV1
      CATEGORY_MAP = {
        "Flower"      => "Flower",
        "Pre-Rolls"   => "Preroll",
        "Vaporizers"  => "Cartridge",
        "Concentrate" => "Concentrate",
        "Edible"      => "Edible Solid",
        "Tincture"    => "Edible Liquid",
        "Topicals"    => "Topical",
        "Accessories" => "Accessories",
      }.freeze

      # Subcategory overrides for Edible
      SUBCATEGORY_OVERRIDES = {
        "drinks" => "Edible Liquid",
      }.freeze

      def flatten(file_path)
        unless File.extname(file_path).downcase == ".xlsx"
          raise ArgumentError, "This doesn't look like a Dutchie product export. Please upload the original .xlsx file from Dutchie."
        end

        begin
          xlsx = Roo::Excelx.new(file_path)
        rescue => e
          raise ArgumentError, "This doesn't look like a valid Dutchie product export. Make sure you're uploading the original Excel file (.xlsx) from Dutchie."
        end

        data_sheet = find_data_sheet(xlsx)
        unless data_sheet
          xlsx.close
          raise ArgumentError, "This doesn't look like a Dutchie product export. Expected a sheet starting with 'multi_brand_catalog' but found: #{xlsx.sheets.join(", ")}"
        end

        xlsx.default_sheet = data_sheet
        if xlsx.last_row.nil? || xlsx.last_row < 2
          xlsx.close
          raise ArgumentError, "The data sheet appears to be empty."
        end

        headers = read_headers(xlsx)

        all_rows = []
        all_columns = Set.new(headers)
        stats = Hash.new { |h, k| h[k] = { total: 0, kept: 0 } }

        (2..xlsx.last_row).each do |row_num|
          raw = read_row(xlsx, headers, row_num)

          product_name = raw["Product Name"]
          brand_name = raw["Brand Name"]
          next if product_name.nil? || (product_name.is_a?(String) && product_name.strip.empty?)
          next if brand_name.nil? || (brand_name.is_a?(String) && brand_name.strip.empty?)

          category = resolve_category(raw["Category"], raw["Subcategory"])
          next unless category

          stats[category][:total] += 1

          raw["_source_sheet"] = data_sheet
          raw["_product_category"] = category
          raw["_source_subcategory"] = raw["Subcategory"]&.to_s&.strip
          raw["_source_row"] = row_num
          raw["_image_url"] = first_image_url(raw, headers)
          raw["_terpenes"] = collapse_terpenes(raw, headers)
          raw["_lineage"] = raw["Type"]&.to_s&.strip

          weight, pack_size = parse_weight_and_pack(product_name.to_s)
          raw["_parsed_weight"] = weight
          raw["_parsed_pack_size"] = pack_size

          all_rows << raw
          stats[category][:kept] += 1
        end

        xlsx.close

        synthetic = %w[_source_sheet _product_category _source_subcategory _source_row
                       _image_url _terpenes _lineage _parsed_weight _parsed_pack_size]
        synthetic.each { |s| all_columns.add(s) }
        ordered_columns = synthetic + (all_columns.to_a - synthetic).sort

        { rows: all_rows, columns: ordered_columns, stats: stats }
      end

      private

      def find_data_sheet(xlsx)
        xlsx.sheets.find { |s| s.strip.start_with?("multi_brand_catalog") }
      end

      def resolve_category(category, subcategory)
        return nil if category.nil? || (category.is_a?(String) && category.strip.empty?)

        cat = category.strip
        subcat = subcategory&.to_s&.strip&.downcase

        # Subcategory overrides for Edible
        if cat == "Edible" && subcat && SUBCATEGORY_OVERRIDES.key?(subcat)
          return SUBCATEGORY_OVERRIDES[subcat]
        end

        CATEGORY_MAP[cat]
      end

      def collapse_terpenes(row, headers)
        terpene_pairs = []

        # Find all Terpene name columns and pair with their value columns
        headers.each_with_index do |h, idx|
          next unless h&.match?(/\ATerpene(\s*\(\d+\))?\z/)
          name = row[h]&.to_s&.strip
          next if name.nil? || name.empty?

          # Value column is the next header matching "Terpene value*"
          value_header = headers[idx + 1]
          value = value_header && value_header.match?(/\ATerpene value/i) ? row[value_header] : nil

          if value
            terpene_pairs << "#{name} (#{value})"
          else
            terpene_pairs << name
          end
        end

        terpene_pairs.empty? ? nil : terpene_pairs.join(", ")
      end

      def first_image_url(row, headers)
        image_headers = headers.select { |h| h&.match?(/\AImage/i) }
        image_headers.each do |h|
          val = row[h]
          return val if val.is_a?(String) && val.match?(/\Ahttps?:\/\//i)
        end
        nil
      end

      def parse_weight_and_pack(product_name)
        weight = nil
        pack_size = nil

        # "2x0.5g" pattern → pack_size=2, weight=0.5
        if product_name =~ /(\d+)\s*x\s*(\d+(?:\.\d+)?)\s*g\b/i
          pack_size = $1.to_i
          weight = $2.to_f
        # "3.5g" or "1g" standalone weight
        elsif product_name =~ /(\d+(?:\.\d+)?)\s*g\b/i
          weight = $1.to_f
        end

        [weight, pack_size]
      end

      def read_headers(xlsx)
        raw = (1..(xlsx.last_column || 0)).map { |c| xlsx.cell(1, c) }
        raw.pop while raw.any? && raw.last.nil?
        raw.map { |h| h&.strip }
      end

      def read_row(xlsx, headers, row_num)
        row = {}
        headers.each_with_index do |header, idx|
          next if header.nil?
          row[header] = xlsx.cell(row_num, idx + 1)
        end
        row
      end
    end

    Registry.register_adapter("dutchie_v1", DutchieV1)
  end
end
