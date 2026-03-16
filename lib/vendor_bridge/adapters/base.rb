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

      # Human-readable name for this source system.
      # Used in the context file and UI.
      def source_label
        self.class.name.split("::").last.sub(/V\d+$/, "")
      end

      # Maps vendor product categories to POSaBIT product_type_name values.
      # Override in subclass.
      #
      # @return [Hash<String, String>] e.g. { "Flower" => "Flower", "Vape" => "Cartridge" }
      def category_mapping
        {}
      end

      # Maps vendor column names to POSaBIT column names.
      # The context builder uses this to generate the field guide.
      # Override in subclass.
      #
      # @return [Array<Hash>] each hash has :vendor, :posabit, :notes keys
      def field_mapping
        []
      end
    end
  end
end
