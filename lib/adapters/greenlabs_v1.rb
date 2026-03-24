require "roo"
require_relative "registry"

module VendorBridge
  module Adapters
    class GreenlabsV1
      DATA_SHEET = "CSV Template"

      SKIP_SHEETS = [
        "Revised", "Assets", "Archived", "Template", "Tags", "Categories"
      ].freeze

      # Map the first segment of the comma-separated Categories value
      # to a normalized product category used in the rosetta stone.
      CATEGORY_MAP = {
        "Infused Pre Roll" => "Infused Preroll",
        "Vape Pens"        => "Vape",
        "Edibles"          => "Edible",
        "Drinks"           => "Drink",
        "Wellness"         => "Wellness",
      }.freeze

      def flatten(file_path)
        unless File.extname(file_path).downcase == ".xlsx"
          raise ArgumentError, "This doesn't look like a Green Labs product export. Please upload the original .xlsx file."
        end

        begin
          xlsx = Roo::Excelx.new(file_path)
        rescue => e
          raise ArgumentError, "This doesn't look like a valid Green Labs product export. Make sure you're uploading the original Excel file (.xlsx)."
        end

        unless xlsx.sheets.include?(DATA_SHEET)
          xlsx.close
          raise ArgumentError, "This doesn't look like a Green Labs product export. Expected a '#{DATA_SHEET}' sheet but found: #{xlsx.sheets.join(", ")}"
        end

        xlsx.default_sheet = DATA_SHEET
        if xlsx.last_row.nil? || xlsx.last_row < 2
          xlsx.close
          raise ArgumentError, "The '#{DATA_SHEET}' sheet appears to be empty."
        end

        headers = read_headers(xlsx)
        cat_col_idx = headers.index("Categories")

        all_rows = []
        all_columns = Set.new(headers)
        stats = Hash.new { |h, k| h[k] = { total: 0, kept: 0 } }

        (2..xlsx.last_row).each do |row_num|
          raw = read_row(xlsx, headers, row_num)

          # Skip empty rows (no product name)
          product = raw["Product"]
          next if product.nil? || (product.is_a?(String) && product.strip.empty?)

          categories_val = raw["Categories"] || ""
          first_segment = categories_val.split(",").first&.strip || "Unknown"
          category = CATEGORY_MAP[first_segment] || first_segment

          stats[category][:total] += 1

          raw["_source_sheet"] = DATA_SHEET
          raw["_product_category"] = category
          raw["_source_category"] = categories_val.strip
          raw["_source_row"] = row_num

          all_rows << raw
          stats[category][:kept] += 1
        end

        xlsx.close

        all_columns.add("_source_category")
        synthetic = %w[_source_sheet _product_category _source_category _source_row]
        ordered_columns = synthetic + (all_columns.to_a - synthetic).sort

        { rows: all_rows, columns: ordered_columns, stats: stats }
      end

      private

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

    Registry.register_adapter("greenlabs_v1", GreenlabsV1)
  end
end
