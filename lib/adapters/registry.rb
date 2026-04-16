require "yaml"

module VendorBridge
  module Adapters
    class Registry
      CONFIG_PATH = File.expand_path("../../../config/rosetta_stone.yaml", __FILE__)

      # Adapter class lookup — maps adapter key from YAML to Ruby class
      ADAPTER_CLASSES = {}

      class << self
        def config
          @config ||= YAML.safe_load_file(CONFIG_PATH)
        end

        def sources
          config["sources"] || {}
        end

        def field_mappings
          config["field_mappings"] || {}
        end

        # Returns list of registered source names (e.g. ["iheartjane"])
        def available
          sources.keys
        end

        # Returns source config hash with label, adapter, category_mapping,
        # plus a derived field_mapping array for context_builder compatibility.
        #
        # @return [Hash] e.g. { "label" => "iHeartJane", "category_mapping" => {...},
        #                       "field_mapping" => [{vendor:, posabit:, notes:}, ...] }
        def fetch(name)
          src = sources.fetch(name.to_s) do
            raise ArgumentError, "Unknown source '#{name}'. Available: #{available.join(", ")}"
          end

          global_warnings = config["warning_rules"] || []
          source_warnings = src["warning_rules"] || []

          src.merge(
            "field_mapping"                  => field_mapping_for(name.to_s),
            "warning_rules"                  => global_warnings + source_warnings,
            "concentrate_type_rules"         => config["concentrate_type_rules"],
            "product_type_correction_rules"  => config["product_type_correction_rules"]
          )
        end

        # Instantiates the Ruby flatten class for a given source.
        def adapter_for(name)
          src = sources.fetch(name.to_s) do
            raise ArgumentError, "Unknown source '#{name}'. Available: #{available.join(", ")}"
          end

          adapter_key = src["adapter"]
          klass = ADAPTER_CLASSES.fetch(adapter_key) do
            raise ArgumentError, "No adapter class registered for '#{adapter_key}'"
          end

          klass.new
        end

        # Called by adapter files to register their flatten class.
        # e.g. Registry.register_adapter("iheartjane_v1", IheartjaneV1)
        def register_adapter(key, klass)
          ADAPTER_CLASSES[key.to_s] = klass
        end

        # Reload config (useful in tests or after YAML edits)
        def reload!
          @config = nil
        end

        private

        # Derives [{vendor:, posabit:, notes:}] array for a specific source
        # from the rosetta stone field_mappings.
        def field_mapping_for(source_name)
          field_mappings.each_with_object([]) do |(posabit_field, mapping), result|
            vendor_col = mapping[source_name]
            next unless vendor_col

            result << {
              "vendor"  => vendor_col,
              "posabit" => posabit_field,
              "notes"   => mapping["notes"] || "",
            }
          end
        end
      end
    end
  end
end
