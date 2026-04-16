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
    expect(md).to include("Concentrate type category guard")
  end

  context "with name cleanup rules" do
    it "renders pattern, action, and example" do
      pipeline = base_pipeline.merge(
        "name_cleanup_rules" => [
          {
            "pattern" => "(DOH Compliant)",
            "action" => "Remove anywhere in the name.",
            "example" => "'Blue Dream - Flower (DOH Compliant)' → 'Blue Dream'",
          },
          {
            "pattern" => "- Flower / - BB's",
            "action" => "Remove format suffixes after a dash",
          },
        ]
      )
      builder = described_class.new(pipeline)
      md = builder.generate(data_dir: data_dir)

      expect(md).to include("Product Name Cleanup Rules")
      expect(md).to include("`(DOH Compliant)`")
      expect(md).to include("Remove anywhere in the name.")
      expect(md).to include("Blue Dream")
      expect(md).to include("`- Flower / - BB's`")
    end
  end

  context "with cross-category matching" do
    it "renders cross-category search instructions" do
      pipeline = base_pipeline.merge(
        "cross_category_matching" => {
          "Edible Liquid" => ["Edible Solid"],
          "Edible Solid" => ["Edible Liquid"],
          "notes" => "Passion Flower RTM products may cross categories.",
        }
      )
      builder = described_class.new(pipeline)
      md = builder.generate(data_dir: data_dir)

      expect(md).to include("Cross-Category Matching")
      expect(md).to include("Edible Liquid")
      expect(md).to include("Also search Edible Solid")
      expect(md).to include("Passion Flower RTM")
    end
  end

  it "renders field mapping as a markdown table" do
    builder = described_class.new(base_pipeline)
    md = builder.generate(data_dir: data_dir)

    expect(md).to include("| Vendor Column | POSaBIT Column | Notes |")
    expect(md).to include("| `Brand` | `brand_name` |")
    expect(md).to include("| `Strain` | `strain_name` |")
  end

  it "references cover_image_url in decision and audit sections" do
    builder = described_class.new(base_pipeline)
    md = builder.generate(data_dir: data_dir)

    expect(md).to include("cover_image_url")
    expect(md).not_to match(/\bimage_url\b(?!s)/)  # no bare "image_url" (but "image_urls" ok)
  end

  it "wraps posabit columns in a code block" do
    builder = described_class.new(base_pipeline)
    md = builder.generate(data_dir: data_dir)

    expect(md).to include("```\nid,active,name,brand_name,strain_name\n```")
  end

  context "source_name audit column" do
    it "includes source_name in audit trail section" do
      builder = described_class.new(base_pipeline)
      md = builder.generate(data_dir: data_dir)

      expect(md).to include("**`source_name`**")
    end

    it "references the explicit vendor column from field mapping" do
      pipeline = base_pipeline.merge(
        "field_mapping" => [
          { "vendor" => "Brand", "posabit" => "brand_name", "notes" => "" },
          { "vendor" => "Strain", "posabit" => "strain_name", "notes" => "" },
          { "vendor" => "Product Name", "posabit" => "source_name", "notes" => "" },
        ]
      )
      builder = described_class.new(pipeline)
      md = builder.generate(data_dir: data_dir)

      expect(md).to include("copy the `Product Name` column")
      expect(md).to include("`Product Name` value from the vendor row")
    end

    it "falls back to Product Name when no source_name mapping exists" do
      pipeline = base_pipeline.merge(
        "field_mapping" => [
          { "vendor" => "Brand", "posabit" => "brand_name", "notes" => "" },
        ]
      )
      builder = described_class.new(pipeline)
      md = builder.generate(data_dir: data_dir)

      expect(md).to include("copy the `Product Name` column")
    end
  end

  context "with warning_rules" do
    let(:pipeline_with_warnings) do
      base_pipeline.merge(
        "warning_rules" => [
          {
            "id" => "capsule_tincture_mismatch",
            "trigger" => "Updating cover_image_url on Edible Solid/Liquid/Capsule",
            "condition" => "Vendor source category suggests different product form",
            "warning_text" => "capsule/tincture mismatch",
            "action" => "Do NOT apply the image.",
          },
          {
            "id" => "lineage_precision_loss",
            "trigger" => "Updating lineage",
            "condition" => "New value less specific than existing",
            "warning_text" => "lineage precision loss",
            "action" => "Keep the original value.",
          },
        ]
      )
    end

    it "renders each warning rule in audit trail" do
      builder = described_class.new(pipeline_with_warnings)
      md = builder.generate(data_dir: data_dir)

      expect(md).to include("`capsule/tincture mismatch`")
      expect(md).to include("`lineage precision loss`")
    end

    it "renders prominent warning rules table" do
      builder = described_class.new(pipeline_with_warnings)
      md = builder.generate(data_dir: data_dir)

      expect(md).to include("IMPORTANT: Warning Rules")
      expect(md).to include("| Warning | When | Condition | Action |")
    end

    it "includes trigger and action in table rows" do
      builder = described_class.new(pipeline_with_warnings)
      md = builder.generate(data_dir: data_dir)

      expect(md).to include("Updating cover_image_url")
      expect(md).to include("Do NOT apply the image.")
    end
  end

  context "with empty warning_rules" do
    it "shows no-rules fallback" do
      pipeline = base_pipeline.merge("warning_rules" => [])
      builder = described_class.new(pipeline)
      md = builder.generate(data_dir: data_dir)

      expect(md).to include("No warning rules defined")
      expect(md).not_to include("IMPORTANT: Warning Rules")
    end
  end

  context "with nil warning_rules" do
    it "shows no-rules fallback without crash" do
      pipeline = base_pipeline.merge("warning_rules" => nil)
      builder = described_class.new(pipeline)
      md = builder.generate(data_dir: data_dir)

      expect(md).to include("No warning rules defined")
    end
  end

  context "with concentrate_type_rules" do
    let(:pipeline_with_concentrate) do
      base_pipeline.merge(
        "concentrate_type_rules" => {
          "canonical_values" => ["Live Resin", "BHO", "Wax", "Rosin"],
          "apply_to_categories" => ["Concentrate", "Cartridge"],
          "inference_by_source" => {
            "iheartjane" => [
              { "field" => "Product Name", "method" => "keyword_scan" },
            ],
          },
          "notes" => "Only populate for Concentrate and Cartridge categories.",
        }
      )
    end

    it "renders concentrate type section with prominent heading" do
      builder = described_class.new(pipeline_with_concentrate)
      md = builder.generate(data_dir: data_dir)

      expect(md).to include("## IMPORTANT: Concentrate Type Extraction")
      expect(md).to include("**MUST** check concentrate type")
      expect(md).to include("**never** invent or use values outside this list")
    end

    it "lists canonical values" do
      builder = described_class.new(pipeline_with_concentrate)
      md = builder.generate(data_dir: data_dir)

      expect(md).to include("`Live Resin`")
      expect(md).to include("`BHO`")
      expect(md).to include("`Wax`")
      expect(md).to include("`Rosin`")
    end

    it "renders source-specific keyword scan rules" do
      builder = described_class.new(pipeline_with_concentrate)
      md = builder.generate(data_dir: data_dir)

      expect(md).to include("`Product Name`")
      expect(md).to include("keyword")
    end

    it "renders applicable categories" do
      builder = described_class.new(pipeline_with_concentrate)
      md = builder.generate(data_dir: data_dir)

      expect(md).to include("Concentrate, Cartridge")
    end

    it "renders notes" do
      builder = described_class.new(pipeline_with_concentrate)
      md = builder.generate(data_dir: data_dir)

      expect(md).to include("Only populate for Concentrate and Cartridge")
    end
  end

  context "with concentrate_type_rules including direct mapping" do
    it "renders field mappings" do
      pipeline = base_pipeline.merge(
        "concentrate_type_rules" => {
          "canonical_values" => ["Live Resin", "BHO"],
          "apply_to_categories" => ["Concentrate"],
          "inference_by_source" => {
            "iheartjane" => [
              {
                "field" => "_source_subcategory",
                "mapping" => { "live-resin" => "Live Resin", "bho" => "BHO" },
              },
            ],
          },
        }
      )
      builder = described_class.new(pipeline)
      md = builder.generate(data_dir: data_dir)

      expect(md).to include("`_source_subcategory`")
      expect(md).to include("`live-resin` → `Live Resin`")
      expect(md).to include("`bho` → `BHO`")
    end
  end

  context "with empty concentrate_type_rules" do
    it "omits concentrate type section" do
      pipeline = base_pipeline.merge("concentrate_type_rules" => {})
      builder = described_class.new(pipeline)
      md = builder.generate(data_dir: data_dir)

      expect(md).not_to include("Concentrate Type Extraction")
    end
  end

  context "with nil concentrate_type_rules" do
    it "omits concentrate type section without crash" do
      pipeline = base_pipeline.merge("concentrate_type_rules" => nil)
      builder = described_class.new(pipeline)
      md = builder.generate(data_dir: data_dir)

      expect(md).not_to include("Concentrate Type Extraction")
    end
  end

  context "with concentrate_type_rules including never_apply_to" do
    it "renders the blocklist" do
      pipeline = base_pipeline.merge(
        "concentrate_type_rules" => {
          "canonical_values" => ["Live Resin", "BHO"],
          "apply_to_categories" => ["Concentrate", "Cartridge"],
          "never_apply_to" => ["Flower", "Edible Solid", "Edible Liquid"],
          "inference_by_source" => {
            "iheartjane" => [
              { "field" => "Product Name", "method" => "keyword_scan" },
            ],
          },
          "notes" => "Only for concentrates.",
        }
      )
      builder = described_class.new(pipeline)
      md = builder.generate(data_dir: data_dir)

      expect(md).to include("NEVER set concentrate_type on")
      expect(md).to include("Flower")
      expect(md).to include("Edible Solid")
      expect(md).to include("clear it to blank")
    end
  end

  context "with product_type_correction_rules" do
    let(:pipeline_with_pt_correction) do
      base_pipeline.merge(
        "product_type_correction_rules" => {
          "trigger" => "Cross-category match between Edible Solid and Edible Liquid",
          "action" => "Correct product_type_name to match the vendor's _product_category.",
          "keyword_overrides" => [
            { "keywords" => ["Capsule", "Capsules"], "correct_to" => "Edible Solid" },
            { "keywords" => ["Tincture"], "correct_to" => "Edible Liquid" },
          ],
          "notes" => "The vendor adapter already maps categories correctly.",
        }
      )
    end

    it "renders product type correction section with prominent heading" do
      builder = described_class.new(pipeline_with_pt_correction)
      md = builder.generate(data_dir: data_dir)

      expect(md).to include("## IMPORTANT: Product Type Correction")
      expect(md).to include("**MUST** correct")
    end

    it "renders keyword overrides" do
      builder = described_class.new(pipeline_with_pt_correction)
      md = builder.generate(data_dir: data_dir)

      expect(md).to include("`Capsule`")
      expect(md).to include("Edible Solid")
      expect(md).to include("`Tincture`")
      expect(md).to include("Edible Liquid")
    end

    it "renders trigger and action" do
      builder = described_class.new(pipeline_with_pt_correction)
      md = builder.generate(data_dir: data_dir)

      expect(md).to include("Cross-category match")
      expect(md).to include("Correct product_type_name")
    end
  end

  context "with empty product_type_correction_rules" do
    it "omits product type correction section" do
      pipeline = base_pipeline.merge("product_type_correction_rules" => {})
      builder = described_class.new(pipeline)
      md = builder.generate(data_dir: data_dir)

      expect(md).not_to include("## IMPORTANT: Product Type Correction")
    end
  end

  context "with nil product_type_correction_rules" do
    it "omits product type correction section without crash" do
      pipeline = base_pipeline.merge("product_type_correction_rules" => nil)
      builder = described_class.new(pipeline)
      md = builder.generate(data_dir: data_dir)

      expect(md).not_to include("## IMPORTANT: Product Type Correction")
    end
  end
end
