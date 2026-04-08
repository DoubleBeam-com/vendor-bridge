require "csv"
require "set"
require_relative "registry"

module VendorBridge
  module Adapters
    class CultiveraV1
      HEADER_SKIP_ROWS = 3

      REQUIRED_HEADERS = %w[Product Product-Line SKU].freeze

      PRODUCT_LINE_MAP = {
        "100% Flower Pre-Rolls"                      => "Preroll",
        "100% Flower Pre-Rolls - Multi-Strain Packs" => "Preroll",
        "Kief Infused Pre-Rolls"                     => "Preroll",
        "Shatter Infused Pre-Rolls"                  => "Preroll",
        "Premium Flower"                             => "Flower",
        "Bulk"                                       => "Flower",
      }.freeze

      def flatten(file_path)
        validate_file!(file_path)

        lines = File.readlines(file_path, encoding: "bom|utf-8")
        vendor_name = extract_vendor_name(lines[0])
        headers = parse_headers(lines)

        all_rows = []
        all_columns = Set.new(headers)
        stats = Hash.new { |h, k| h[k] = { total: 0, kept: 0 } }

        data_lines = lines[(HEADER_SKIP_ROWS + 1)..]
        data_lines&.each_with_index do |line, idx|
          row_num = idx + HEADER_SKIP_ROWS + 2 # 1-based, accounting for skipped rows + header
          raw = parse_row(line, headers)
          next if raw.nil?

          product = raw["Product"]&.to_s&.strip
          next if product.nil? || product.empty?

          product_line = raw["Product-Line"]&.to_s&.strip
          next if product_line.nil? || product_line.empty?

          # Filter CATALOG duplicates, COMING SOON, Trade Samples
          next if product_line.match?(/\ACATALOG\b/i)
          next if product.match?(/\ACOMING SOON\b/i)
          next if product.match?(/\ATrade Sample\b/i)

          category = resolve_category(product_line)
          stats[category][:total] += 1

          strain, weight, pack_size = parse_product_name(product)

          raw["_source_sheet"] = "CSV"
          raw["_product_category"] = category
          raw["_source_subcategory"] = product_line
          raw["_source_row"] = row_num
          raw["_parsed_strain"] = strain
          raw["_parsed_weight"] = weight
          raw["_parsed_pack_size"] = pack_size
          raw["_sku"] = raw["SKU"]&.to_s&.strip
          raw["_vendor_name"] = vendor_name
          raw["_price"] = parse_price(raw["Price"])

          all_rows << raw
          stats[category][:kept] += 1
        end

        synthetic = %w[
          _source_sheet _product_category _source_subcategory
          _source_row _parsed_strain _parsed_weight
          _parsed_pack_size _sku _vendor_name _price
        ]
        synthetic.each { |s| all_columns.add(s) }
        ordered_columns = synthetic + (all_columns.to_a - synthetic).sort

        { rows: all_rows, columns: ordered_columns, stats: stats }
      end

      private

      def validate_file!(file_path)
        ext = File.extname(file_path).downcase
        unless ext == ".csv"
          raise ArgumentError,
            "This doesn't look like a Cultivera inventory export. " \
            "Please upload a CSV file. If you have an XLSX, export " \
            "it as CSV first (File > Download > CSV in Google Sheets)."
        end
      end

      def extract_vendor_name(title_line)
        return nil if title_line.nil?

        clean = title_line.encode("UTF-8", invalid: :replace, undef: :replace)
                          .sub(/\A\xEF\xBB\xBF/, "")
                          .strip
        match = clean.match(/Currently Available Inventory\s+(?:for\s+)?(.+)/i)
        match ? match[1].split(",").first.strip : nil
      end

      def parse_headers(lines)
        header_line = lines[HEADER_SKIP_ROWS]
        raise ArgumentError, "File appears to be empty or too short." if header_line.nil?

        headers = CSV.parse_line(header_line)&.map { |h| h&.strip }
        raise ArgumentError, "Could not parse headers from the file." if headers.nil? || headers.empty?

        missing = REQUIRED_HEADERS - headers.compact
        unless missing.empty?
          raise ArgumentError,
            "This doesn't look like a Cultivera inventory export. " \
            "Missing expected columns: #{missing.join(", ")}. " \
            "Found: #{headers.compact.join(", ")}"
        end

        headers
      end

      def parse_row(line, headers)
        return nil if line.nil? || line.strip.empty?

        values = CSV.parse_line(line)
        return nil if values.nil?

        row = {}
        headers.each_with_index do |header, idx|
          next if header.nil?
          row[header] = values[idx]
        end
        row
      rescue CSV::MalformedCSVError
        nil
      end

      def resolve_category(product_line)
        PRODUCT_LINE_MAP[product_line] || product_line
      end

      def parse_product_name(product)
        name = product.to_s.strip
        weight = nil
        pack_size = nil
        strain = nil

        # "10-pack x 0.5g" pattern → pack_size + per-unit weight
        if name =~ /(\d+)-pack\s*x\s*(\d+(?:\.\d+)?)g\s*\z/i
          pack_size = $1.to_i
          weight = $2.to_f
        # "03.5g" or "1g" standalone weight at end
        elsif name =~ /(\d+(?:\.\d+)?)g\s*\z/i
          weight = $1.to_f
        end

        # Extract strain from middle of "Type - Strain - Pack/Weight"
        parts = name.split(/\s+-\s+/)
        if parts.size >= 3
          strain = parts[1..-2].join(" - ").strip
        elsif parts.size == 2
          # "Premium Flower - Wedding Cake - 01g" may have been split
          candidate = parts.last
                          .sub(/\s*\d+-pack\s*x\s*\d+(?:\.\d+)?g\s*\z/i, "")
                          .sub(/\s*\d+(?:\.\d+)?g\s*\z/i, "")
                          .strip
          strain = candidate unless candidate.empty?
        end

        [strain, weight, pack_size]
      end

      def parse_price(price_str)
        return nil if price_str.nil?

        clean = price_str.to_s.gsub(/[^0-9.]/, "")
        clean.empty? ? nil : clean.to_f
      end
    end

    Registry.register_adapter("cultivera_v1", CultiveraV1)
  end
end
