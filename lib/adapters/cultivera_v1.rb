require 'csv'
require 'set'
require_relative 'registry'

module VendorBridge
  module Adapters
    class CultiveraV1
      HEADER_SKIP_ROWS = 3

      REQUIRED_HEADERS = %w[Product Product-Line SKU].freeze

      PRODUCT_LINE_MAP = {
        '100% Flower Pre-Rolls' => 'Preroll',
        '100% Flower Pre-Rolls - Multi-Strain Packs' => 'Preroll',
        'Kief Infused Pre-Rolls' => 'Preroll',
        'Shatter Infused Pre-Rolls' => 'Preroll',
        'Premium Flower' => 'Flower',
        'Bulk' => 'Flower'
      }.freeze

      SYNTHETIC_COLUMNS = %w[
        _source_sheet _product_category _source_subcategory
        _source_row _parsed_strain _parsed_weight
        _parsed_pack_size _sku _vendor_name _price
      ].freeze

      def flatten(file_path)
        validate_file!(file_path)

        lines = File.readlines(file_path, encoding: 'bom|utf-8')
        vendor_name = extract_vendor_name(lines[0])
        headers = parse_headers(lines)

        all_rows = []
        stats = Hash.new { |h, k| h[k] = { total: 0, kept: 0 } }

        data_lines = lines[(HEADER_SKIP_ROWS + 1)..]
        data_lines&.each_with_index do |line, idx|
          row_num = idx + HEADER_SKIP_ROWS + 2
          row = process_data_row(line, headers, vendor_name, row_num, stats)
          all_rows << row if row
        end

        { rows: all_rows, columns: build_columns(headers), stats: stats }
      end

      private

      def process_data_row(line, headers, vendor_name, row_num, stats)
        raw = parse_row(line, headers)
        return nil if raw.nil?

        product = raw['Product'].to_s.strip
        product_line = raw['Product-Line'].to_s.strip
        return nil if product.empty? || product_line.empty?
        return nil if skip_row?(product, product_line)

        category = resolve_category(product_line)
        stats[category][:total] += 1
        enrich_row(raw, category: category, product: product,
                        product_line: product_line, vendor_name: vendor_name, row_num: row_num)
        stats[category][:kept] += 1
        raw
      end

      def skip_row?(product, product_line)
        product_line.match?(/\ACATALOG\b/i) ||
          product.match?(/\ACOMING SOON\b/i) ||
          product.match?(/\ATrade Sample\b/i)
      end

      def enrich_row(raw, context)
        strain, weight, pack_size = parse_product_name(context[:product])
        raw['_source_sheet'] = 'CSV'
        raw['_product_category'] = context[:category]
        raw['_source_subcategory'] = context[:product_line]
        raw['_source_row'] = context[:row_num]
        raw['_parsed_strain'] = strain
        raw['_parsed_weight'] = weight
        raw['_parsed_pack_size'] = pack_size
        raw['_sku'] = raw['SKU'].to_s.strip
        raw['_vendor_name'] = context[:vendor_name]
        raw['_price'] = parse_price(raw['Price'])
      end

      def build_columns(headers)
        all = Set.new(headers)
        SYNTHETIC_COLUMNS.each { |s| all.add(s) }
        SYNTHETIC_COLUMNS + (all.to_a - SYNTHETIC_COLUMNS).sort
      end

      def validate_file!(file_path)
        ext = File.extname(file_path).downcase
        return if ext == '.csv'

        raise ArgumentError,
              "This doesn't look like a Cultivera inventory export. " \
              'Please upload a CSV file. If you have an XLSX, export ' \
              'it as CSV first (File > Download > CSV in Google Sheets).'
      end

      def extract_vendor_name(title_line)
        return nil if title_line.nil?

        clean = title_line.encode('UTF-8', invalid: :replace, undef: :replace)
                          .sub(/\A\xEF\xBB\xBF/, '')
                          .strip
        match = clean.match(/Currently Available Inventory\s+(?:for\s+)?(.+)/i)
        match ? match[1].split(',').first.strip : nil
      end

      def parse_headers(lines)
        header_line = lines[HEADER_SKIP_ROWS]
        raise ArgumentError, 'File appears to be empty or too short.' if header_line.nil?

        headers = CSV.parse_line(header_line)&.map { |h| h&.strip }
        raise ArgumentError, 'Could not parse headers from the file.' if headers.nil? || headers.empty?

        validate_required_headers!(headers)
        headers
      end

      def validate_required_headers!(headers)
        missing = REQUIRED_HEADERS - headers.compact
        return if missing.empty?

        raise ArgumentError,
              "This doesn't look like a Cultivera inventory export. " \
              "Missing expected columns: #{missing.join(', ')}. " \
              "Found: #{headers.compact.join(', ')}"
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
          pack_size = ::Regexp.last_match(1).to_i
          weight = ::Regexp.last_match(2).to_f
        # "03.5g" or "1g" standalone weight at end
        elsif name =~ /(\d+(?:\.\d+)?)g\s*\z/i
          weight = ::Regexp.last_match(1).to_f
        end

        # Extract strain from middle of "Type - Strain - Pack/Weight"
        parts = name.split(/\s+-\s+/)
        if parts.size >= 3
          strain = parts[1..-2].join(' - ').strip
        elsif parts.size == 2
          # "Premium Flower - Wedding Cake - 01g" may have been split
          candidate = parts.last
                           .sub(/\s*\d+-pack\s*x\s*\d+(?:\.\d+)?g\s*\z/i, '')
                           .sub(/\s*\d+(?:\.\d+)?g\s*\z/i, '')
                           .strip
          strain = candidate unless candidate.empty?
        end

        [strain, weight, pack_size]
      end

      def parse_price(price_str)
        return nil if price_str.nil?

        clean = price_str.to_s.gsub(/[^0-9.]/, '')
        clean.empty? ? nil : clean.to_f
      end
    end

    Registry.register_adapter('cultivera_v1', CultiveraV1)
  end
end
