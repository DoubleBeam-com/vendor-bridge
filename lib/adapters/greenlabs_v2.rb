require "roo"
require_relative "registry"

module VendorBridge
  module Adapters
    class GreenlabsV2
      EXPECTED_HEADERS = ["Vendor", "Venue", "All Active Products", "Products In Stock"].freeze
      SKIP_SHEETS = ["Pivot Table 1"].freeze

      def flatten(file_path)
        unless File.extname(file_path).downcase == ".xlsx"
          raise ArgumentError, "This doesn't look like a Green Labs inventory export. Please upload the original .xlsx file."
        end

        begin
          xlsx = Roo::Excelx.new(file_path)
        rescue => e
          raise ArgumentError, "This doesn't look like a valid Green Labs inventory export. Make sure you're uploading the original Excel file (.xlsx)."
        end

        data_sheets = xlsx.sheets.select { |s| !SKIP_SHEETS.include?(s) && has_expected_headers?(xlsx, s) }
        if data_sheets.empty?
          xlsx.close
          raise ArgumentError, "This doesn't look like a Green Labs inventory export. Expected sheets with columns: #{EXPECTED_HEADERS.join(", ")}. Found sheets: #{xlsx.sheets.join(", ")}"
        end

        seen = Set.new
        all_rows = []
        stats = Hash.new { |h, k| h[k] = { total: 0, kept: 0 } }

        data_sheets.each do |sheet_name|
          xlsx.default_sheet = sheet_name
          next if xlsx.last_row.nil? || xlsx.last_row < 2

          headers = read_headers(xlsx)

          (2..xlsx.last_row).each do |row_num|
            raw = read_row(xlsx, headers, row_num)

            vendor = raw["Vendor"]
            next if vendor.nil? || (vendor.is_a?(String) && vendor.strip.empty?)

            venue = raw["Venue"] || ""
            dedup_key = "#{vendor.strip.downcase}|#{venue.strip.downcase}"

            stats[sheet_name][:total] += 1

            next if seen.include?(dedup_key)
            seen.add(dedup_key)

            raw["_source_sheet"] = sheet_name
            raw["_source_row"] = row_num

            all_rows << raw
            stats[sheet_name][:kept] += 1
          end
        end

        xlsx.close

        synthetic = %w[_source_sheet _source_row]
        ordered_columns = synthetic + EXPECTED_HEADERS
        { rows: all_rows, columns: ordered_columns, stats: stats }
      end

      private

      def has_expected_headers?(xlsx, sheet_name)
        xlsx.default_sheet = sheet_name
        return false if xlsx.last_row.nil? || xlsx.last_row < 1
        headers = (1..(xlsx.last_column || 0)).map { |c| xlsx.cell(1, c)&.strip }
        EXPECTED_HEADERS.all? { |h| headers.include?(h) }
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

    Registry.register_adapter("greenlabs_v2", GreenlabsV2)
  end
end
