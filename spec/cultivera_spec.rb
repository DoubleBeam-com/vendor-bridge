require_relative 'spec_helper'

RSpec.describe 'Cultivera adapter' do
  let(:csv_path) { fixture_path('cultivera_sample.csv') }

  describe VendorBridge::Adapters::CultiveraV1 do
    let(:adapter) { VendorBridge::Adapters::CultiveraV1.new }

    it 'flattens the Cultivera CSV into rows' do
      result = adapter.flatten(csv_path)

      expect(result[:rows]).to be_an(Array)
      expect(result[:rows].size).to be > 0
      expect(result[:columns]).to include(
        '_source_sheet', '_product_category', '_source_row',
        '_source_subcategory', '_parsed_strain', '_parsed_weight',
        '_parsed_pack_size', '_sku', '_vendor_name', '_price'
      )
      expect(result[:columns]).to include('Product', 'Product-Line', 'SKU')
    end

    it 'filters out CATALOG duplicate rows' do
      result = adapter.flatten(csv_path)
      product_lines = result[:rows].map { |r| r['Product-Line'] }

      expect(product_lines.none? { |pl| pl&.match?(/\ACATALOG/i) }).to be true
    end

    it 'filters out COMING SOON rows' do
      result = adapter.flatten(csv_path)
      products = result[:rows].map { |r| r['Product'] }

      expect(products.none? { |p| p&.match?(/\ACOMING SOON/i) }).to be true
    end

    it 'filters out Trade Sample rows' do
      result = adapter.flatten(csv_path)
      products = result[:rows].map { |r| r['Product'] }

      expect(products.none? { |p| p&.match?(/\ATrade Sample/i) }).to be true
    end

    it 'maps Product-Line to _product_category' do
      result = adapter.flatten(csv_path)
      categories = result[:rows].map { |r| r['_product_category'] }.uniq.sort

      expect(categories).to include('Preroll')
    end

    it 'maps all preroll types to Preroll' do
      result = adapter.flatten(csv_path)
      preroll_sources = result[:rows]
                        .select { |r| r['_product_category'] == 'Preroll' }
                        .map { |r| r['_source_subcategory'] }
                        .uniq
                        .sort

      expect(preroll_sources).to include('100% Flower Pre-Rolls')
    end

    it 'parses strain name from product name' do
      result = adapter.flatten(csv_path)
      king_louie = result[:rows].find { |r| r['Product']&.include?('King Louie') }

      expect(king_louie).not_to be_nil
      expect(king_louie['_parsed_strain']).to eq('King Louie')
    end

    it 'parses pack size from product name' do
      result = adapter.flatten(csv_path)
      ten_pack = result[:rows].find do |r|
        r['Product']&.include?('King Louie') &&
          r['Product'].include?('10-pack')
      end

      expect(ten_pack).not_to be_nil
      expect(ten_pack['_parsed_pack_size']).to eq(10)
    end

    it 'parses per-unit weight from product name' do
      result = adapter.flatten(csv_path)
      row = result[:rows].find do |r|
        r['Product']&.include?('King Louie') &&
          r['Product'].include?('10-pack x 0.5g')
      end

      expect(row).not_to be_nil
      expect(row['_parsed_weight']).to eq(0.5)
    end

    it 'handles premium flower weight format' do
      result = adapter.flatten(csv_path)
      row = result[:rows].find { |r| r['Product']&.include?('Premium Flower - Wedding Cake - 03.5g') }

      expect(row).not_to be_nil
      expect(row['_parsed_strain']).to eq('Wedding Cake')
      expect(row['_parsed_weight']).to eq(3.5)
    end

    it 'extracts vendor name from title row' do
      result = adapter.flatten(csv_path)

      expect(result[:rows].first['_vendor_name']).to eq('The Happy Cannabis')
    end

    it 'strips dollar sign from price' do
      result = adapter.flatten(csv_path)
      row = result[:rows].find { |r| r['_price']&.positive? }

      expect(row).not_to be_nil
      expect(row['_price']).to be_a(Float)
    end

    it 'preserves SKU as _sku' do
      result = adapter.flatten(csv_path)

      result[:rows].each do |row|
        expect(row['_sku']).not_to be_nil
        expect(row['_sku']).not_to be_empty
        expect(row['_sku']).to eq(row['SKU']&.strip)
      end
    end

    it 'provides stats per category' do
      result = adapter.flatten(csv_path)

      expect(result[:stats]).to be_a(Hash)
      expect(result[:stats].values).to all(have_key(:total))
      expect(result[:stats].values).to all(have_key(:kept))
    end

    it 'orders columns with synthetic fields first' do
      result = adapter.flatten(csv_path)
      first_col = result[:columns].first

      expect(first_col).to eq('_source_sheet')
    end

    it 'rejects non-CSV files' do
      expect do
        adapter.flatten(File.join(__dir__, 'fixtures/garbage.xlsx'))
      end.to raise_error(ArgumentError, /Cultivera/)
    end
  end

  describe 'Web flow', type: :request do
    it 'processes upload and redirects to preview' do
      post '/upload',
           source: 'cultivera',
           file: Rack::Test::UploadedFile.new(csv_path, 'text/csv')

      expect(last_response.status).to eq(302)
      location = last_response.headers['Location']
      expect(location).to match(%r{/preview/\w+})

      get location
      expect(last_response).to be_ok
      expect(last_response.body).to include('Products Extracted')
    end

    it 'exports flattened CSV with _sku column' do
      post '/upload',
           source: 'cultivera',
           file: Rack::Test::UploadedFile.new(csv_path, 'text/csv')

      location = last_response.headers['Location']
      id = location.split('/').last

      get "/export/#{id}"
      expect(last_response.status).to eq(200)
      expect(last_response.headers['Content-Type']).to include('text/csv')
      expect(last_response.body).to include('_sku')
      expect(last_response.body).to include('_product_category')
    end
  end

  describe 'Registry integration' do
    it 'lists cultivera as an available source' do
      VendorBridge::Adapters::Registry.reload!
      expect(VendorBridge::Adapters::Registry.available).to include('cultivera')
    end

    it 'fetches cultivera config with sku_reference field mapping' do
      VendorBridge::Adapters::Registry.reload!
      config = VendorBridge::Adapters::Registry.fetch('cultivera')

      expect(config['label']).to eq('Cultivera')
      expect(config['category_mapping']).to include('Preroll' => 'Preroll')
      expect(config['field_mapping']).to be_an(Array)
      posabit_fields = config['field_mapping'].map { |m| m['posabit'] }
      expect(posabit_fields).to include('sku_reference')
    end
  end
end
