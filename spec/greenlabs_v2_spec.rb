require_relative "spec_helper"

RSpec.describe "Green Labs Inventory adapter" do
  let(:xlsx_path) { File.join(__dir__, "../samples/green_labs.xlsx") }

  describe VendorBridge::Adapters::GreenlabsV2 do
    let(:adapter) { VendorBridge::Adapters::GreenlabsV2.new }

    it "flattens the inventory XLSX into rows" do
      result = adapter.flatten(xlsx_path)

      expect(result[:rows]).to be_an(Array)
      expect(result[:rows].size).to be > 0
      expect(result[:columns]).to include("_source_sheet", "_source_row", "Vendor", "Venue", "All Active Products", "Products In Stock")
    end

    it "deduplicates across sheets" do
      result = adapter.flatten(xlsx_path)

      # Vendor+Venue pairs should be unique
      pairs = result[:rows].map { |r| "#{r["Vendor"]}|#{r["Venue"]}" }
      expect(pairs.size).to eq(pairs.uniq.size)
    end

    it "skips rows with blank vendor" do
      result = adapter.flatten(xlsx_path)

      vendors = result[:rows].map { |r| r["Vendor"] }
      expect(vendors).to all(be_a(String).and(satisfy { |v| !v.strip.empty? }))
    end

    it "provides stats per sheet" do
      result = adapter.flatten(xlsx_path)

      expect(result[:stats]).to be_a(Hash)
      expect(result[:stats].keys).to include("Sheet1")
      result[:stats].each_value do |s|
        expect(s).to have_key(:total)
        expect(s).to have_key(:kept)
      end
    end

    it "skips Pivot Table 1 sheet" do
      result = adapter.flatten(xlsx_path)

      sheets = result[:rows].map { |r| r["_source_sheet"] }.uniq
      expect(sheets).not_to include("Pivot Table 1")
    end

    it "rejects non-XLSX files" do
      expect {
        adapter.flatten(File.join(__dir__, "fixtures/not_an_xlsx.csv"))
      }.to raise_error(ArgumentError, /Green Labs/)
    end

    it "rejects XLSX files without expected headers" do
      expect {
        adapter.flatten(File.join(__dir__, "fixtures/garbage.xlsx"))
      }.to raise_error(ArgumentError, /Green Labs/)
    end
  end

  describe "Web flow", type: :request do
    it "processes upload and redirects to preview" do
      post "/upload",
        source: "greenlabs_inventory",
        file: Rack::Test::UploadedFile.new(xlsx_path, "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet")

      expect(last_response.status).to eq(302)
      location = last_response.headers["Location"]
      expect(location).to match(%r{/preview/\w+})
    end
  end

  describe "Registry integration" do
    it "lists greenlabs_inventory as an available source" do
      VendorBridge::Adapters::Registry.reload!
      expect(VendorBridge::Adapters::Registry.available).to include("greenlabs_inventory")
    end

    it "fetches config with field mappings including quantity_on_hand" do
      VendorBridge::Adapters::Registry.reload!
      config = VendorBridge::Adapters::Registry.fetch("greenlabs_inventory")

      expect(config["label"]).to eq("Green Labs Inventory")
      field_posabit = config["field_mapping"].map { |m| m["posabit"] }
      expect(field_posabit).to include("brand_name", "quantity_on_hand")
    end
  end
end
