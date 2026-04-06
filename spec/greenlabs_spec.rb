require_relative "spec_helper"

RSpec.describe "Green Labs adapter" do
  let(:xlsx_path) { fixture_path("greenlabs_products_sample.xlsx") }

  describe VendorBridge::Adapters::GreenlabsV1 do
    let(:adapter) { VendorBridge::Adapters::GreenlabsV1.new }

    it "flattens the Green Labs XLSX into rows" do
      result = adapter.flatten(xlsx_path)

      expect(result[:rows]).to be_an(Array)
      expect(result[:rows].size).to be > 0
      expect(result[:columns]).to include("_source_sheet", "_product_category", "_source_row", "_source_category")
      expect(result[:columns]).to include("Product", "DESCRIPTION", "Categories", "STRAIN")
    end

    it "maps categories correctly" do
      result = adapter.flatten(xlsx_path)
      categories = result[:rows].map { |r| r["_product_category"] }.uniq.sort

      expect(categories).to include("Infused Preroll", "Vape")
    end

    it "preserves the full source category string" do
      result = adapter.flatten(xlsx_path)
      source_cats = result[:rows].map { |r| r["_source_category"] }.compact.uniq

      expect(source_cats.any? { |c| c.include?(",") }).to be true
    end

    it "provides stats per category" do
      result = adapter.flatten(xlsx_path)

      expect(result[:stats]).to be_a(Hash)
      expect(result[:stats].values).to all(have_key(:total))
      expect(result[:stats].values).to all(have_key(:kept))
    end

    it "rejects non-XLSX files" do
      expect {
        adapter.flatten(File.join(__dir__, "fixtures/not_an_xlsx.csv"))
      }.to raise_error(ArgumentError, /Green Labs/)
    end

    it "rejects XLSX files without CSV Template sheet" do
      expect {
        adapter.flatten(File.join(__dir__, "fixtures/garbage.xlsx"))
      }.to raise_error(ArgumentError, /Green Labs|CSV Template/)
    end
  end

  describe "Web flow", type: :request do
    it "processes upload and redirects to preview" do
      post "/upload",
        source: "greenlabs",
        file: Rack::Test::UploadedFile.new(xlsx_path, "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet")

      expect(last_response.status).to eq(302)
      location = last_response.headers["Location"]
      expect(location).to match(%r{/preview/\w+})

      # Follow redirect and verify preview content
      get location
      expect(last_response).to be_ok
      expect(last_response.body).to include("Products Extracted")
      expect(last_response.body).to include("greenlabs_products_sample.xlsx")
    end

    it "exports flattened CSV" do
      post "/upload",
        source: "greenlabs",
        file: Rack::Test::UploadedFile.new(xlsx_path, "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet")

      location = last_response.headers["Location"]
      id = location.split("/").last

      get "/export/#{id}"
      expect(last_response.status).to eq(200)
      expect(last_response.headers["Content-Type"]).to include("text/csv")
      expect(last_response.body).to include("_product_category")
    end
  end

  describe "Registry integration" do
    it "lists greenlabs as an available source" do
      VendorBridge::Adapters::Registry.reload!
      expect(VendorBridge::Adapters::Registry.available).to include("greenlabs")
    end

    it "fetches greenlabs config with field mappings" do
      VendorBridge::Adapters::Registry.reload!
      config = VendorBridge::Adapters::Registry.fetch("greenlabs")

      expect(config["label"]).to eq("Green Labs")
      expect(config["category_mapping"]).to include("Infused Preroll" => "Preroll")
      expect(config["field_mapping"]).to be_an(Array)
      expect(config["field_mapping"].map { |m| m["posabit"] }).to include("strain_name", "description", "cover_image_url")
    end
  end
end
