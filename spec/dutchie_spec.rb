require_relative "spec_helper"

RSpec.describe "Dutchie adapter" do
  let(:xlsx_path) { fixture_path("dutchie_sample.xlsx") }

  describe VendorBridge::Adapters::DutchieV1 do
    let(:adapter) { VendorBridge::Adapters::DutchieV1.new }

    it "flattens the Dutchie XLSX into rows" do
      result = adapter.flatten(xlsx_path)

      expect(result[:rows]).to be_an(Array)
      expect(result[:rows].size).to be > 0
      expect(result[:columns]).to include(
        "_source_sheet", "_product_category", "_source_subcategory", "_source_row",
        "_cover_image_url", "_image_urls", "_terpenes", "_lineage", "_parsed_weight", "_parsed_pack_size"
      )
      expect(result[:columns]).to include("Product Name", "Brand Name", "Category")
    end

    it "maps categories correctly" do
      result = adapter.flatten(xlsx_path)
      categories = result[:rows].map { |r| r["_product_category"] }.uniq.sort

      expect(categories).to include("Flower", "Preroll", "Cartridge", "Concentrate")
    end

    it "maps Edible drinks subcategory to Edible Liquid" do
      result = adapter.flatten(xlsx_path)
      drinks = result[:rows].select { |r| r["Category"] == "Edible" && r["Subcategory"] == "drinks" }

      expect(drinks).not_to be_empty
      drinks.each do |row|
        expect(row["_product_category"]).to eq("Edible Liquid")
      end
    end

    it "maps Tincture to Edible Liquid" do
      result = adapter.flatten(xlsx_path)
      tinctures = result[:rows].select { |r| r["Category"] == "Tincture" }

      expect(tinctures).not_to be_empty
      tinctures.each do |row|
        expect(row["_product_category"]).to eq("Edible Liquid")
      end
    end

    it "maps Vaporizers to Cartridge" do
      result = adapter.flatten(xlsx_path)
      vapes = result[:rows].select { |r| r["Category"] == "Vaporizers" }

      expect(vapes).not_to be_empty
      vapes.each do |row|
        expect(row["_product_category"]).to eq("Cartridge")
      end
    end

    it "picks the first image URL into _cover_image_url" do
      result = adapter.flatten(xlsx_path)
      with_image = result[:rows].select { |r| r["_cover_image_url"] }

      expect(with_image).not_to be_empty
      with_image.each do |row|
        expect(row["_cover_image_url"]).to match(/\Ahttps?:\/\//)
      end
    end

    it "collects additional image URLs into _image_urls" do
      result = adapter.flatten(xlsx_path)
      with_additional = result[:rows].select { |r| r["_image_urls"] }

      with_additional.each do |row|
        row["_image_urls"].split(", ").each do |url|
          expect(url).to match(/\Ahttps?:\/\//)
        end
      end
    end

    it "sets _lineage from the Type column" do
      result = adapter.flatten(xlsx_path)
      lineages = result[:rows].map { |r| r["_lineage"] }.compact.uniq

      expect(lineages).to include("Hybrid", "Indica", "Sativa")
    end

    it "parses weight and pack size from product names" do
      result = adapter.flatten(xlsx_path)

      # Find a preroll with pack info like "2x0.5g"
      preroll = result[:rows].find { |r| r["Product Name"]&.match?(/\d+x\d+/) }
      if preroll
        expect(preroll["_parsed_pack_size"]).to be_a(Integer)
        expect(preroll["_parsed_weight"]).to be_a(Float)
      end

      # Find a flower with standalone weight like "3.5g"
      flower = result[:rows].find { |r| r["Product Name"]&.match?(/\d+(?:\.\d+)?g\b/) && !r["Product Name"]&.match?(/\dx/) }
      if flower
        expect(flower["_parsed_weight"]).to be_a(Float)
      end
    end

    it "provides stats per category" do
      result = adapter.flatten(xlsx_path)

      expect(result[:stats]).to be_a(Hash)
      expect(result[:stats].values).to all(have_key(:total))
      expect(result[:stats].values).to all(have_key(:kept))
    end

    it "preserves the source subcategory" do
      result = adapter.flatten(xlsx_path)
      subcats = result[:rows].map { |r| r["_source_subcategory"] }.compact.reject(&:empty?).uniq

      expect(subcats).to include("packs")
    end

    it "rejects non-XLSX files" do
      expect {
        adapter.flatten(File.join(__dir__, "fixtures/not_an_xlsx.csv"))
      }.to raise_error(ArgumentError, /Dutchie/)
    end

    it "rejects XLSX files without multi_brand_catalog sheet" do
      expect {
        adapter.flatten(File.join(__dir__, "fixtures/garbage.xlsx"))
      }.to raise_error(ArgumentError, /Dutchie|multi_brand_catalog/)
    end
  end

  describe "Web flow", type: :request do
    it "processes upload and redirects to preview" do
      post "/upload",
        source: "dutchie",
        file: Rack::Test::UploadedFile.new(xlsx_path, "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet")

      expect(last_response.status).to eq(302)
      location = last_response.headers["Location"]
      expect(location).to match(%r{/preview/\w+})

      get location
      expect(last_response).to be_ok
      expect(last_response.body).to include("Products Extracted")
      expect(last_response.body).to include("dutchie_sample.xlsx")
    end

    it "exports flattened CSV" do
      post "/upload",
        source: "dutchie",
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
    it "lists dutchie as an available source" do
      VendorBridge::Adapters::Registry.reload!
      expect(VendorBridge::Adapters::Registry.available).to include("dutchie")
    end

    it "fetches dutchie config with field mappings" do
      VendorBridge::Adapters::Registry.reload!
      config = VendorBridge::Adapters::Registry.fetch("dutchie")

      expect(config["label"]).to eq("Dutchie")
      expect(config["category_mapping"]).to include("Flower" => "Flower")
      expect(config["category_mapping"]).to include("Preroll" => "Preroll")
      expect(config["field_mapping"]).to be_an(Array)
      expect(config["field_mapping"].map { |m| m["posabit"] }).to include("brand_name", "description", "cover_image_url", "image_urls", "terpenes", "lineage")
    end
  end
end
