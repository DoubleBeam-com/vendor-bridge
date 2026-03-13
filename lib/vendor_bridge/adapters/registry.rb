module VendorBridge
  module Adapters
    class Registry
      class << self
        def adapters
          @adapters ||= {}
        end

        def register(name, klass)
          adapters[name.to_s] = klass
        end

        def fetch(name)
          adapters.fetch(name.to_s) do
            available = adapters.keys.join(", ")
            raise ArgumentError, "Unknown source '#{name}'. Available: #{available}"
          end
        end

        def available
          adapters.keys
        end
      end
    end
  end
end
