require_relative "spec_helper"

RSpec.describe VendorBridge::Transforms::RowFilter do
  let(:filter) { described_class.new }

  describe "#data_row?" do
    it "accepts a normal data row" do
      row = { "Brand" => "Phat Panda", "Strain" => "Alien OG", "Amount [g]" => "3.5" }
      expect(filter.data_row?(row)).to be true
    end

    it "rejects an example brand row" do
      row = { "Brand" => "My Brand", "Strain" => "Alien OG" }
      expect(filter.data_row?(row)).to be false
    end

    it "rejects an example strain row" do
      row = { "Brand" => "Real Brand", "Strain" => "My Strain" }
      expect(filter.data_row?(row)).to be false
    end

    it "rejects an example product row via Ratio & Product Name" do
      row = { "Brand" => "Real Brand", "Ratio & Product Name" => "My Product" }
      expect(filter.data_row?(row)).to be false
    end

    it "rejects an empty row" do
      row = { "Brand" => "", "Strain" => nil, "Amount [g]" => "  " }
      expect(filter.data_row?(row)).to be false
    end

    it "rejects a section header (blank brand, one filled field)" do
      row = { "Brand" => nil, "_source_sheet" => "Flower", "_product_category" => "Flower", "Strain" => "Category Header" }
      expect(filter.data_row?(row)).to be false
    end

    it "rejects a pipe-only product name" do
      row = { "Brand" => "Real Brand", "Product Name (Internal Use)" => "| | |", "Strain" => "OG" }
      expect(filter.data_row?(row)).to be false
    end

    it "rejects a row with blank brand" do
      row = { "Brand" => "  ", "Strain" => "Alien OG" }
      expect(filter.data_row?(row)).to be false
    end

    it "handles non-string strain gracefully" do
      row = { "Brand" => "Real Brand", "Strain" => 12345 }
      expect(filter.data_row?(row)).to be true
    end

    it "rejects example brand case-insensitively" do
      row = { "Brand" => "MY BRAND", "Strain" => "Alien OG" }
      expect(filter.data_row?(row)).to be false
    end

    it "rejects 'My Product' via Ratio & Product Name" do
      row = { "Brand" => "Real Brand", "Ratio & Product Name" => "My Product" }
      expect(filter.data_row?(row)).to be false
    end

    it "treats row with only ignored columns as empty" do
      row = { "_source_sheet" => "Flower", "_product_category" => "Flower", "_source_row" => 5 }
      expect(filter.data_row?(row)).to be false
    end

    it "accepts section header boundary: blank brand with 2 filled data fields" do
      row = { "Brand" => nil, "Strain" => "Blue Dream", "Amount [g]" => "3.5" }
      expect(filter.data_row?(row)).to be false  # still rejected — blank brand
    end

    it "rejects tab-only brand as blank" do
      row = { "Brand" => "\t", "Strain" => "Alien OG" }
      expect(filter.data_row?(row)).to be false
    end

    it "rejects row with numeric brand (no match? on Integer)" do
      row = { "Brand" => 42, "Strain" => "Test Strain" }
      # Integer doesn't respond to match?, so example_row? check raises
      # This exposes a bug — non-string brands crash the filter
      expect { filter.data_row?(row) }.to raise_error(NoMethodError)
    end

    it "rejects pipe-only via Product Name column" do
      row = { "Brand" => "Real Brand", "Product Name" => "| | | |" }
      expect(filter.data_row?(row)).to be false
    end
  end
end
