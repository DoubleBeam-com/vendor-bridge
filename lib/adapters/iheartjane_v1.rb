require "roo"
require_relative "registry"
require_relative "../transforms/row_filter"

module VendorBridge
  module Adapters
    class IheartjaneV1
      SKIP_SHEETS = ["Intructions", "Product Card"].freeze

      CATEGORY_MAP = {
        "Flower"                => "Flower",
        "Pre-RollInfused"       => "Preroll",
        "Edible"                => "Edible",
        "Extract (concentrates)" => "Concentrate",
        "Vape"                  => "Vape",
        "Topical"               => "Topical",
        "Gear"                  => "Gear",
        "Merch."                => "Merchandise",
      }.freeze

      def flatten(file_path)
        unless File.extname(file_path).downcase == ".xlsx"
          raise ArgumentError, "This doesn't look like an iHeartJane product template. Please upload the original .xlsx file from iHeartJane."
        end

        begin
          xlsx = Roo::Excelx.new(file_path)
        rescue => e
          raise ArgumentError, "This doesn't look like a valid iHeartJane product template. Make sure you're uploading the original Excel file (.xlsx) from iHeartJane, not a CSV or other format."
        end

        # Validate it has at least one expected product sheet
        expected_sheets = CATEGORY_MAP.keys
        found = xlsx.sheets.select { |s| expected_sheets.include?(s) }
        if found.empty?
          xlsx.close
          raise ArgumentError, "This doesn't look like an iHeartJane product template. Expected sheets like Flower, Edible, or Vape but found: #{xlsx.sheets.join(", ")}"
        end

        filter = Transforms::RowFilter.new

        all_rows = []
        all_columns = Set.new
        stats = {}

        xlsx.sheets.each do |sheet_name|
          next if SKIP_SHEETS.include?(sheet_name)

          category = CATEGORY_MAP[sheet_name]
          next unless category

          xlsx.default_sheet = sheet_name
          next if xlsx.last_row.nil? || xlsx.last_row < 2

          headers = read_headers(xlsx, sheet_name)
          all_columns.merge(headers)

          total = 0
          kept = 0

          (2..xlsx.last_row).each do |row_num|
            raw = read_row(xlsx, headers, row_num)
            total += 1

            next unless filter.data_row?(raw)

            raw["_source_sheet"] = sheet_name
            raw["_product_category"] = category
            raw["_source_row"] = row_num

            all_rows << raw
            kept += 1
          end

          stats[sheet_name] = { total: total, kept: kept }
        end

        xlsx.close

        synthetic = %w[_source_sheet _product_category _source_row]
        ordered_columns = synthetic + all_columns.to_a.sort

        { rows: all_rows, columns: ordered_columns, stats: stats }
      end

      private

      def read_headers(xlsx, sheet_name)
        raw_headers = (1..(xlsx.last_column || 0)).map { |c| xlsx.cell(1, c) }

        # Flower sheet has nil in column 1 — default to "Brand"
        raw_headers[0] = "Brand" if raw_headers[0].nil? && sheet_name == "Flower"

        # Strip trailing nil columns (Vape, Merch.)
        raw_headers.pop while raw_headers.any? && raw_headers.last.nil?

        # Clean whitespace from header names
        raw_headers.map { |h| h&.strip }
      end

      def read_row(xlsx, headers, row_num)
        row = {}
        headers.each_with_index do |header, idx|
          next if header.nil?
          col = idx + 1
          val = xlsx.cell(row_num, col)

          # Image columns store URLs as hyperlinks, not cell text.
          # Prefer the hyperlink URL when available.
          if val && header =~ /image/i
            link = xlsx.hyperlink(row_num, col) rescue nil
            val = link if link && link =~ /\Ahttps?:\/\//i
          end

          row[header] = val
        end
        row
      end
    end

    Registry.register_adapter("iheartjane_v1", IheartjaneV1)
  end
end
