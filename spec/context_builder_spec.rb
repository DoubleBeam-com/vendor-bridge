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
end
