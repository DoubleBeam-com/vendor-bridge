module VendorBridge
  module Adapters
    class Base
      # Flatten a source file into a uniform array of product hashes.
      #
      # @param file_path [String] path to the source file (XLSX, CSV, JSON, etc.)
      # @return [Hash] { rows: Array<Hash>, columns: Array<String>, stats: Hash }
      #   - rows: flat product hashes keyed by original column names,
      #           plus synthetic keys `_source_sheet` and `_product_category`
      #   - columns: union of all column names across all rows
      #   - stats: per-category counts, e.g. { "Flower" => { total: 100, kept: 80 } }
      def flatten(file_path)
        raise NotImplementedError, "#{self.class}#flatten must be implemented"
      end
    end
  end
end
