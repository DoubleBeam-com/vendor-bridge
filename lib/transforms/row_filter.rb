module VendorBridge
  module Transforms
    class RowFilter
      # Columns to ignore when checking if a row has real data
      IGNORE_COLUMNS = [
        "Jane Use: Click here when product is added",
        "Jane Use",
        "Product Name (Internal Use)",
        "Product Name",
        "_source_sheet",
        "_product_category",
        "_source_row",
      ].freeze

      EXAMPLE_BRANDS = /\Amy brand\z/i
      EXAMPLE_STRAINS = /\Amy (strain|product)\z/i
      PIPE_ONLY = /\A[\s|]+\z/

      def data_row?(row)
        return false if example_row?(row)
        return false if empty_row?(row)
        return false if section_header?(row)
        return false if pipe_only_name?(row)
        return false if blank_brand?(row)
        true
      end

      private

      def example_row?(row)
        brand = row_brand(row)
        return true if brand&.match?(EXAMPLE_BRANDS)

        strain = row["Strain"] || row["Ratio & Product Name"]
        return true if strain.is_a?(String) && strain.match?(EXAMPLE_STRAINS)

        false
      end

      def empty_row?(row)
        data_values(row).all? { |v| v.nil? || (v.is_a?(String) && v.strip.empty?) }
      end

      def section_header?(row)
        brand = row_brand(row)
        return false unless brand.nil? || (brand.is_a?(String) && brand.strip.empty?)

        filled = data_values(row).count { |v| v && (!v.is_a?(String) || !v.strip.empty?) }
        filled <= 1
      end

      def pipe_only_name?(row)
        name = row["Product Name (Internal Use)"] || row["Product Name"]
        return false unless name.is_a?(String)
        name.match?(PIPE_ONLY)
      end

      def blank_brand?(row)
        brand = row_brand(row)
        brand.nil? || (brand.is_a?(String) && brand.strip.empty?)
      end

      def row_brand(row)
        row["Brand"]
      end

      def data_values(row)
        row.reject { |k, _| IGNORE_COLUMNS.include?(k) }.values
      end
    end
  end
end
