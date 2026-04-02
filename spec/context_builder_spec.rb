require_relative "spec_helper"

RSpec.describe VendorBridge::Adapters::ContextBuilder do
  let(:base_pipeline) do
    {
      "source" => "iheartjane",
      "source_label" => "iHeartJane",
      "category_mapping" => { "Flower" => "Flower", "Vape" => "Cartridge" },
      "field_mapping" => [
        { "vendor" => "Brand", "posabit" => "brand_name", "notes" => "" },
        { "vendor" => "Strain", "posabit" => "strain_name", "notes" => "" },
      ],
      "matching_hints" => { "Flower" => "Match on brand + strain only." },
      "posabit_columns" => %w[id active name brand_name strain_name],
    }
  end

  let(:data_dir) { File.join(File.dirname(__dir__), "data_files") }

  it "generates context with all sections" do
    builder = described_class.new(base_pipeline)
    md = builder.generate(data_dir: data_dir)

    expect(md).to include("POSaBIT Product Reconciliation")
    expect(md).to include("Canonical Values")
    expect(md).to include("iheartjane_flattened.csv")
    expect(md).to include("`Flower` → `Flower`")
    expect(md).to include("id,active,name,brand_name,strain_name")
    expect(md).to include("Per-category matching notes")
    expect(md).to include("Vendor-to-POSaBIT field guide")
  end

  context "with empty category mapping" do
    it "shows no-mapping message" do
      pipeline = base_pipeline.merge("category_mapping" => {})
      builder = described_class.new(pipeline)
      md = builder.generate(data_dir: data_dir)

      expect(md).to include("No category mapping defined")
    end
  end

  context "with empty matching hints" do
    it "omits per-category notes section" do
      pipeline = base_pipeline.merge("matching_hints" => {})
      builder = described_class.new(pipeline)
      md = builder.generate(data_dir: data_dir)

      expect(md).not_to include("Per-category matching notes")
    end
  end

  context "with nil matching hints" do
    it "omits per-category notes section" do
      pipeline = base_pipeline.merge("matching_hints" => nil)
      builder = described_class.new(pipeline)
      md = builder.generate(data_dir: data_dir)

      expect(md).not_to include("Per-category matching notes")
    end
  end

  context "with empty field mapping" do
    it "omits field guide section" do
      pipeline = base_pipeline.merge("field_mapping" => [])
      builder = described_class.new(pipeline)
      md = builder.generate(data_dir: data_dir)

      expect(md).not_to include("Vendor-to-POSaBIT field guide")
    end
  end

  context "with empty posabit columns" do
    it "omits column list" do
      pipeline = base_pipeline.merge("posabit_columns" => [])
      builder = described_class.new(pipeline)
      md = builder.generate(data_dir: data_dir)

      expect(md).not_to include("Use these exact columns")
    end
  end

  context "with disambiguating fields" do
    it "includes vendor fields section" do
      pipeline = base_pipeline.merge(
        "disambiguating_fields" => {
          "_source_subcategory" => {
            "description" => "Subcategory slug from vendor",
            "values" => { "small-buds" => "BB's product line" },
          },
        }
      )
      builder = described_class.new(pipeline)
      md = builder.generate(data_dir: data_dir)

      expect(md).to include("Vendor Fields for Disambiguation")
      expect(md).to include("`_source_subcategory`")
      expect(md).to include("`small-buds`")
      expect(md).to include("BB's product line")
    end
  end

  context "with empty disambiguating fields" do
    it "omits vendor fields section" do
      pipeline = base_pipeline.merge("disambiguating_fields" => {})
      builder = described_class.new(pipeline)
      md = builder.generate(data_dir: data_dir)

      expect(md).not_to include("Vendor Fields for Disambiguation")
    end
  end

  context "with matching examples" do
    it "includes examples section" do
      pipeline = base_pipeline.merge(
        "matching_examples" => [
          {
            "vendor_name" => "Blue Dream - BB's",
            "vendor_fields" => "_source_subcategory: small-buds",
            "posabit_name" => "Flower BB's - Blue Dream - 3.5g",
            "action" => "UPDATE",
            "reasoning" => "BB's suffix means small-buds line",
          },
        ]
      )
      builder = described_class.new(pipeline)
      md = builder.generate(data_dir: data_dir)

      expect(md).to include("Matching Examples")
      expect(md).to include("`Blue Dream - BB's`")
      expect(md).to include("`Flower BB's - Blue Dream - 3.5g`")
      expect(md).to include("UPDATE")
    end
  end

  context "with empty matching examples" do
    it "omits examples section" do
      pipeline = base_pipeline.merge("matching_examples" => [])
      builder = described_class.new(pipeline)
      md = builder.generate(data_dir: data_dir)

      expect(md).not_to include("Matching Examples")
    end
  end

  it "always includes verification checklist" do
    builder = described_class.new(base_pipeline)
    md = builder.generate(data_dir: data_dir)

    expect(md).to include("Pre-Submit Verification")
    expect(md).to include("INSERT audit")
    expect(md).to include("Lineage sanity check")
  end
end
