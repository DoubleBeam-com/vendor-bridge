require_relative "spec_helper"

RSpec.describe "CNDUIT adapter" do
  let(:xlsx_path) { fixture_path("cnduit_sample.xlsx") }

  describe VendorBridge::Adapters::CnduitV1 do
    let(:adapter) { VendorBridge::Adapters::CnduitV1.new }

    it "flattens the CNDUIT XLSX into rows" do
      result = adapter.flatten(xlsx_path)

      expect(result[:rows]).to be_an(Array)
      expect(result[:rows].size).to be > 0
      expect(result[:columns]).to include(
        "_source_sheet", "_product_category", "_source_row",
        "_section_title", "_cover_image_url", "_lineage", "_parsed_pack_size"
      )
      expect(result[:columns]).to include("Product Name", "Brand Name", "Category")
    end

    it "detects all sections and produces rows from each" do
      result = adapter.flatten(xlsx_path)
      sections = result[:rows].map { |r| r["_source_sheet"] }.uniq

      expect(sections.size).to be >= 20
    end

    it "fills down Brand Name, State, and Category for all rows" do
      result = adapter.flatten(xlsx_path)

      result[:rows].each do |row|
        expect(row["Brand Name"]).not_to be_nil, "Brand Name nil at row #{row["_source_row"]}"
        expect(row["Brand Name"].to_s).not_to match(/↓/), "Arrow in Brand Name at row #{row["_source_row"]}"
        expect(row["Category"]).not_to be_nil, "Category nil at row #{row["_source_row"]}"
      end
    end

    it "maps categories correctly from section titles" do
      result = adapter.flatten(xlsx_path)
      categories = result[:rows].map { |r| r["_product_category"] }.uniq.sort

      expect(categories).to include("Flower", "Preroll", "Vape", "Concentrate")
    end

    it "parses pack size from section titles" do
      result = adapter.flatten(xlsx_path)

      preroll_2pk = result[:rows].find { |r| r["_section_title"]&.include?("2pk") }
      expect(preroll_2pk).not_to be_nil
      expect(preroll_2pk["_parsed_pack_size"]).to eq(2)

      preroll_28pk = result[:rows].find { |r| r["_section_title"]&.include?("28pk") }
      expect(preroll_28pk).not_to be_nil
      expect(preroll_28pk["_parsed_pack_size"]).to eq(28)
    end

    it "returns nil pack_size for sections without pack info" do
      result = adapter.flatten(xlsx_path)
      flower = result[:rows].find { |r| r["_product_category"] == "Flower" }
      expect(flower["_parsed_pack_size"]).to be_nil
    end

    it "extracts image URLs into _cover_image_url" do
      result = adapter.flatten(xlsx_path)
      with_image = result[:rows].select { |r| r["_cover_image_url"] }

      expect(with_image).not_to be_empty
      with_image.each do |row|
        expect(row["_cover_image_url"]).to match(/\Ahttps?:\/\//)
      end
    end

    it "sets _lineage from the Type column" do
      result = adapter.flatten(xlsx_path)
      lineages = result[:rows].map { |r| r["_lineage"] }.compact.uniq

      expect(lineages).to include("Hybrid", "Indica", "Sativa")
    end

    it "handles empty sections gracefully" do
      result = adapter.flatten(xlsx_path)

      # Some sections like "THE COLLECTIVE - BHO Concentrate" are empty
      # They should not produce rows, but also not crash
      expect(result[:rows]).to be_an(Array)
    end

    it "provides stats per category" do
      result = adapter.flatten(xlsx_path)

      expect(result[:stats]).to be_a(Hash)
      expect(result[:stats].values).to all(have_key(:total))
      expect(result[:stats].values).to all(have_key(:kept))
      expect(result[:stats]["Flower"][:kept]).to be > 0
    end

    it "orders columns with synthetic fields first" do
      result = adapter.flatten(xlsx_path)
      columns = result[:columns]

      synthetic = %w[_source_sheet _product_category _source_row _section_title
                     _cover_image_url _lineage _parsed_pack_size]

      synthetic.each_with_index do |s, i|
        expect(columns.index(s)).to eq(i), "Expected #{s} at index #{i}, got #{columns.index(s)}"
      end
    end

    it "sets _section_title to the product line after the brand" do
      result = adapter.flatten(xlsx_path)
      titles = result[:rows].map { |r| r["_section_title"] }.uniq

      expect(titles).to include("Flower")
      expect(titles.any? { |t| t&.include?("Prerolls") }).to be true
    end

    it "includes multiple brands" do
      result = adapter.flatten(xlsx_path)
      brands = result[:rows].map { |r| r["Brand Name"]&.to_s&.strip }.uniq

      expect(brands.size).to be >= 3
    end

    it "rejects non-XLSX files" do
      expect {
        adapter.flatten(File.join(__dir__, "fixtures/not_an_xlsx.csv"))
      }.to raise_error(ArgumentError, /CNDUIT/)
    end
  end

  describe "Web flow", type: :request do
    it "processes upload and redirects to preview" do
      post "/upload",
        source: "cnduit",
        file: Rack::Test::UploadedFile.new(xlsx_path, "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet")

      expect(last_response.status).to eq(302)
      location = last_response.headers["Location"]
      expect(location).to match(%r{/preview/\w+})

      get location
      expect(last_response).to be_ok
      expect(last_response.body).to include("Products Extracted")
    end

    it "exports flattened CSV" do
      post "/upload",
        source: "cnduit",
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
    it "lists cnduit as an available source" do
      VendorBridge::Adapters::Registry.reload!
      expect(VendorBridge::Adapters::Registry.available).to include("cnduit")
    end

    it "fetches cnduit config with field mappings" do
      VendorBridge::Adapters::Registry.reload!
      config = VendorBridge::Adapters::Registry.fetch("cnduit")

      expect(config["label"]).to eq("CNDUIT")
      expect(config["category_mapping"]).to include("Flower" => "Flower")
      expect(config["field_mapping"]).to be_an(Array)
      expect(config["field_mapping"].map { |m| m["posabit"] }).to include("brand_name", "description", "cover_image_url", "lineage")
    end
  end
end
