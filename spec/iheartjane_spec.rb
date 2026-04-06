require_relative "spec_helper"

RSpec.describe "iHeartJane adapter" do
  let(:xlsx_path) { File.join(__dir__, "../samples/iheartjane_template.xlsx") }
  let(:sample_exists) { File.exist?(xlsx_path) }

  describe VendorBridge::Adapters::IheartjaneV1, if: File.exist?(File.join(__dir__, "../samples/iheartjane_template.xlsx")) do
    let(:adapter) { VendorBridge::Adapters::IheartjaneV1.new }

    it "flattens the iHeartJane XLSX into rows" do
      result = adapter.flatten(xlsx_path)

      expect(result[:rows]).to be_an(Array)
      expect(result[:rows].size).to be > 0
      expect(result[:columns]).to include("_source_sheet", "_product_category", "_source_row")
    end

    it "maps categories correctly" do
      result = adapter.flatten(xlsx_path)
      categories = result[:rows].map { |r| r["_product_category"] }.uniq.sort

      # Should include at least some of the mapped categories
      known = %w[Flower Preroll Edible Concentrate Vape Topical Gear Merchandise]
      expect(categories & known).not_to be_empty
    end

    it "skips Instructions and Product Card sheets" do
      result = adapter.flatten(xlsx_path)
      sheets = result[:rows].map { |r| r["_source_sheet"] }.uniq

      expect(sheets).not_to include("Intructions")
      expect(sheets).not_to include("Product Card")
    end

    it "assigns _source_row for each row" do
      result = adapter.flatten(xlsx_path)

      result[:rows].each do |row|
        expect(row["_source_row"]).to be_a(Integer)
        expect(row["_source_row"]).to be >= 2
      end
    end

    it "filters out example and empty rows via RowFilter" do
      result = adapter.flatten(xlsx_path)

      result[:rows].each do |row|
        brand = row["Brand"]
        next unless brand.is_a?(String)
        expect(brand.downcase).not_to eq("my brand")
      end
    end

    it "provides stats per sheet" do
      result = adapter.flatten(xlsx_path)

      expect(result[:stats]).to be_a(Hash)
      result[:stats].each do |sheet, counts|
        expect(counts).to have_key(:total)
        expect(counts).to have_key(:kept)
        expect(counts[:kept]).to be <= counts[:total]
      end
    end

    it "orders columns with synthetic fields first" do
      result = adapter.flatten(xlsx_path)
      cols = result[:columns]

      synthetic = %w[_source_sheet _product_category _source_row]
      synthetic.each_with_index do |s, i|
        expect(cols[i]).to eq(s)
      end
    end

    it "defaults Flower sheet nil header to Brand" do
      result = adapter.flatten(xlsx_path)
      flower_rows = result[:rows].select { |r| r["_source_sheet"] == "Flower" }

      # Flower rows should have a Brand column (from nil header fix)
      expect(flower_rows).not_to be_empty
      expect(result[:columns]).to include("Brand")
    end

    it "extracts image hyperlinks when present" do
      result = adapter.flatten(xlsx_path)
      image_cols = result[:columns].select { |c| c =~ /image/i }

      next if image_cols.empty?

      # If any rows have image data, check it's a URL (hyperlink extraction)
      rows_with_images = result[:rows].select { |r| image_cols.any? { |c| r[c].is_a?(String) && r[c] =~ /\Ahttps?:\/\//i } }
      rows_with_images.each do |row|
        image_cols.each do |col|
          val = row[col]
          next unless val.is_a?(String) && !val.strip.empty?
          expect(val).to match(/\Ahttps?:\/\//i)
        end
      end
    end

    it "rejects non-XLSX files" do
      expect {
        adapter.flatten(File.join(__dir__, "fixtures/not_an_xlsx.csv"))
      }.to raise_error(ArgumentError, /iHeartJane/)
    end

    it "rejects XLSX files without expected sheets" do
      expect {
        adapter.flatten(File.join(__dir__, "fixtures/garbage.xlsx"))
      }.to raise_error(ArgumentError, /iHeartJane/)
    end
  end

  describe "Web flow", type: :request, if: File.exist?(File.join(__dir__, "../samples/iheartjane_template.xlsx")) do
    let(:xlsx_path) { File.join(__dir__, "../samples/iheartjane_template.xlsx") }

    it "processes upload and redirects to preview" do
      post "/upload",
        source: "iheartjane",
        file: Rack::Test::UploadedFile.new(xlsx_path, "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet")

      expect(last_response.status).to eq(302)
      location = last_response.headers["Location"]
      expect(location).to match(%r{/preview/\w+})

      get location
      expect(last_response).to be_ok
      expect(last_response.body).to include("Products Extracted")
      expect(last_response.body).to include("iheartjane_template.xlsx")
    end

    it "exports flattened CSV" do
      post "/upload",
        source: "iheartjane",
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
    it "lists iheartjane as an available source" do
      VendorBridge::Adapters::Registry.reload!
      expect(VendorBridge::Adapters::Registry.available).to include("iheartjane")
    end

    it "fetches iheartjane config with field mappings" do
      VendorBridge::Adapters::Registry.reload!
      config = VendorBridge::Adapters::Registry.fetch("iheartjane")

      expect(config["label"]).to eq("iHeartJane")
      expect(config["category_mapping"]).to include("Flower" => "Flower")
      expect(config["field_mapping"]).to be_an(Array)
      expect(config["field_mapping"].map { |m| m["posabit"] }).to include("brand_name", "strain_name", "description", "cover_image_url")
    end

    it "instantiates the adapter via adapter_for" do
      VendorBridge::Adapters::Registry.reload!
      adapter = VendorBridge::Adapters::Registry.adapter_for("iheartjane")

      expect(adapter).to be_a(VendorBridge::Adapters::IheartjaneV1)
    end

    it "raises for unknown source" do
      VendorBridge::Adapters::Registry.reload!
      expect {
        VendorBridge::Adapters::Registry.fetch("nonexistent_source")
      }.to raise_error(ArgumentError, /Unknown source/)
    end
  end
end
