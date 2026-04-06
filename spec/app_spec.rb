require_relative "spec_helper"

RSpec.describe VendorBridge::App do
  describe "GET /" do
    it "renders the upload page" do
      get "/"
      expect(last_response).to be_ok
      expect(last_response.body).to include("Upload Product File")
    end
  end

  describe "POST /upload" do
    context "with no file" do
      it "returns 400" do
        post "/upload", source: "iheartjane"
        expect(last_response.status).to eq(400)
      end
    end

    context "with a CSV instead of XLSX" do
      it "returns 400 with a friendly error" do
        csv_path = fixture_path("not_an_xlsx.csv")
        post "/upload",
          source: "iheartjane",
          file: Rack::Test::UploadedFile.new(csv_path, "text/csv")

        expect(last_response.status).to eq(400)
        expect(last_response.body).to include("iHeartJane")
        expect(last_response.body).not_to include("BACKTRACE")
      end
    end

    context "with a garbage xlsx file" do
      it "returns 400 with a friendly error" do
        garbage_path = fixture_path("garbage.xlsx")
        post "/upload",
          source: "iheartjane",
          file: Rack::Test::UploadedFile.new(garbage_path, "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet")

        expect(last_response.status).to eq(400)
        expect(last_response.body).to include("iHeartJane")
        expect(last_response.body).not_to include("BACKTRACE")
      end
    end

    context "with an unsupported file type" do
      it "returns 400" do
        # Create a temp .txt file
        txt = Tempfile.new(["test", ".txt"])
        txt.write("hello")
        txt.rewind

        post "/upload",
          source: "iheartjane",
          file: Rack::Test::UploadedFile.new(txt.path, "text/plain", original_filename: "test.txt")

        expect(last_response.status).to eq(400)
        expect(last_response.body).to include("Unsupported file type")
        txt.close!
      end
    end

    context "with a valid iHeartJane XLSX", if: File.exist?(File.join(__dir__, "../samples/iheartjane_template.xlsx")) do
      let(:xlsx_path) { File.join(__dir__, "../samples/iheartjane_template.xlsx") }

      it "processes and redirects to preview" do
        post "/upload",
          source: "iheartjane",
          file: Rack::Test::UploadedFile.new(xlsx_path, "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet")

        expect(last_response.status).to eq(302)
        expect(last_response.headers["Location"]).to match(%r{/preview/\w+})
      end
    end
  end

  describe "POST /upload-posabit/:id" do
    let(:pipeline_id) { "testid123" }

    before do
      # Create a minimal pipeline session
      session_dir = File.join(File.dirname(__FILE__), "../tmp/sessions")
      FileUtils.mkdir_p(session_dir)
      pipeline = {
        "id" => pipeline_id,
        "step" => "preview",
        "source" => "iheartjane",
        "filename" => "test.xlsx",
        "rows" => [{ "Brand" => "Test", "_product_category" => "Flower" }],
        "columns" => ["Brand", "_product_category"],
        "stats" => { "Flower" => { "total" => 1, "kept" => 1 } },
      }
      File.write(File.join(session_dir, "#{pipeline_id}.json"), JSON.pretty_generate(pipeline))
    end

    context "with a valid CSV" do
      it "stores POSaBIT metadata and generates context file" do
        csv_path = fixture_path("sample_posabit.csv")
        post "/upload-posabit/#{pipeline_id}",
          posabit_file: Rack::Test::UploadedFile.new(csv_path, "text/csv")

        expect(last_response.status).to eq(302)
        expect(last_response.headers["Location"]).to include("/preview/#{pipeline_id}")

        # Verify metadata was stored (not raw rows)
        pipeline = JSON.parse(File.read(File.join(__dir__, "../tmp/sessions/#{pipeline_id}.json")))
        expect(pipeline["has_posabit"]).to eq(true)
        expect(pipeline["posabit_row_count"]).to eq(2)
        expect(pipeline["posabit_columns"]).to include("id", "brand_name", "strain_name")

        # Verify data file was saved
        data_csv = File.join(__dir__, "../data_files/posabit_data.csv")
        expect(File.exist?(data_csv)).to be true

        # Verify context file was auto-generated
        context_md = File.join(__dir__, "../data_files/reconciliation_context.md")
        expect(File.exist?(context_md)).to be true
        expect(File.read(context_md)).to include("Product Reconciliation")
      end
    end

    context "with no file" do
      it "returns 400" do
        post "/upload-posabit/#{pipeline_id}"
        expect(last_response.status).to eq(400)
      end
    end

    context "with a bad session ID" do
      it "returns 404" do
        csv_path = fixture_path("sample_posabit.csv")
        post "/upload-posabit/nonexistent",
          posabit_file: Rack::Test::UploadedFile.new(csv_path, "text/csv")

        expect(last_response.status).to eq(404)
      end
    end
  end

  describe "GET /export/:id" do
    let(:pipeline_id) { "exporttest1" }
    let(:session_dir) { File.join(File.dirname(__FILE__), "../tmp/sessions") }

    before do
      FileUtils.mkdir_p(session_dir)
      pipeline = {
        "id" => pipeline_id,
        "source" => "iheartjane",
        "filename" => "test.xlsx",
        "rows" => [
          { "Brand" => "Phat Panda", "_product_category" => "Flower", "Strain" => "Alien OG" }
        ],
        "columns" => ["Brand", "_product_category", "Strain"],
        "stats" => { "Flower" => { "total" => 1, "kept" => 1 } },
      }
      File.write(File.join(session_dir, "#{pipeline_id}.json"), JSON.pretty_generate(pipeline))
    end

    it "downloads a CSV file" do
      get "/export/#{pipeline_id}"

      expect(last_response.status).to eq(200)
      expect(last_response.headers["Content-Type"]).to include("text/csv")
      expect(last_response.headers["Content-Disposition"]).to include("test_flattened.csv")
      expect(last_response.body).to include("Phat Panda")
    end

    it "returns 404 for unknown session" do
      get "/export/nonexistent"
      expect(last_response.status).to eq(404)
    end
  end

  describe "GET /context/:id" do
    let(:pipeline_id) { "ctxtest123" }
    let(:session_dir) { File.join(File.dirname(__FILE__), "../tmp/sessions") }
    let(:data_dir) { File.join(File.dirname(__FILE__), "../data_files") }

    before do
      FileUtils.mkdir_p(session_dir)
      FileUtils.mkdir_p(data_dir)
      pipeline = {
        "id" => pipeline_id,
        "source" => "iheartjane",
        "filename" => "test.xlsx",
        "rows" => [],
        "columns" => [],
        "stats" => {},
        "has_posabit" => true,
        "posabit_columns" => ["id", "name", "brand_name", "strain_name", "product_type_name"],
      }
      File.write(File.join(session_dir, "#{pipeline_id}.json"), JSON.pretty_generate(pipeline))
      # Pre-generate the context file (normally done by upload-posabit route)
      File.write(File.join(data_dir, "reconciliation_context.md"), "# POSaBIT Product Reconciliation\nMatching Rules\n")
    end

    it "downloads a markdown context file" do
      get "/context/#{pipeline_id}"

      expect(last_response.status).to eq(200)
      expect(last_response.headers["Content-Type"]).to include("text/markdown")
      expect(last_response.headers["Content-Disposition"]).to include("reconciliation_context.md")
      expect(last_response.body).to include("Product Reconciliation")
    end

    context "without context file on disk" do
      it "returns 400" do
        FileUtils.rm_f(File.join(data_dir, "reconciliation_context.md"))

        get "/context/#{pipeline_id}"
        expect(last_response.status).to eq(400)
      end
    end
  end

  describe "GET /summary/:id" do
    let(:pipeline_id) { "sumtest123" }
    let(:session_dir) { File.join(File.dirname(__FILE__), "../tmp/sessions") }
    let(:data_dir) { File.join(File.dirname(__FILE__), "../data_files") }

    before do
      FileUtils.mkdir_p(session_dir)
      FileUtils.mkdir_p(data_dir)
      pipeline = {
        "id" => pipeline_id,
        "source" => "iheartjane",
        "filename" => "test.xlsx",
        "rows" => [],
        "columns" => [],
        "stats" => {},
      }
      File.write(File.join(session_dir, "#{pipeline_id}.json"), JSON.pretty_generate(pipeline))
    end

    context "without reconciliation output file" do
      it "returns 400" do
        get "/summary/#{pipeline_id}"
        expect(last_response.status).to eq(400)
        expect(last_response.body).to include("Reconciliation output not found")
      end
    end

    context "with reconciliation output" do
      before do
        csv = "id,product_type_name\n1,Flower\n2,Flower\n3,Concentrate\n"
        File.write(File.join(data_dir, "reconciliation_output.csv"), csv)
      end

      it "renders summary page" do
        get "/summary/#{pipeline_id}"
        expect(last_response).to be_ok
      end
    end

    context "with mixed actions output" do
      before do
        FileUtils.cp(fixture_path("summary_mixed.csv"), File.join(data_dir, "reconciliation_output.csv"))
      end

      it "computes correct metrics" do
        get "/summary/#{pipeline_id}"
        expect(last_response).to be_ok

        # 4 updates, 2 inserts = 6 actionable
        # match_rate = 4/6 * 100 = 66.7%
        # multi-field updates: rows 1 (3 fields) and 4 (2 fields) = 2 of 4
        # enrichment_rate = 2/4 * 100 = 50.0%
        # overall = 66.7 * 0.6 + 50.0 * 0.4 = 40.02 + 20.0 = 60.0
        body = last_response.body
        expect(body).to include("66.7")   # match rate
        expect(body).to include("50.0")   # enrichment rate
        expect(body).to include("60.0")   # overall grade
      end

      it "tracks updates and inserts separately" do
        get "/summary/#{pipeline_id}"
        body = last_response.body

        # Should show update details
        expect(body).to include("Blue Dream Flower")
        expect(body).to include("GG#4 Flower")
        # Should show insert details
        expect(body).to include("Grapefruit")
        expect(body).to include("Nag Champa")
      end

      it "groups summary by product type" do
        get "/summary/#{pipeline_id}"
        body = last_response.body

        expect(body).to include("Flower")
        expect(body).to include("Cartridge")
        expect(body).to include("Edible Solid")
      end
    end

    context "with all-inserts output" do
      before do
        FileUtils.cp(fixture_path("summary_all_inserts.csv"), File.join(data_dir, "reconciliation_output.csv"))
      end

      it "computes 0% match rate" do
        get "/summary/#{pipeline_id}"
        expect(last_response).to be_ok

        # 0 updates, 3 inserts → match_rate = 0.0%
        body = last_response.body
        expect(body).to include("0.0")
      end
    end

    context "with legacy _changes_made format" do
      before do
        FileUtils.cp(fixture_path("summary_legacy_format.csv"), File.join(data_dir, "reconciliation_output.csv"))
      end

      it "parses UPDATE and INSERT actions from _changes_made column" do
        get "/summary/#{pipeline_id}"
        expect(last_response).to be_ok

        body = last_response.body
        # 2 updates, 1 insert = 3 actionable
        # match_rate = 2/3 * 100 = 66.7%
        expect(body).to include("66.7")
        # Should recognize the insert
        expect(body).to include("Grapefruit")
      end
    end

    context "with no actionable rows" do
      before do
        csv = "id,name,product_type_name,row_action,updated_fields\n1,Product A,Flower,none,\n2,Product B,Flower,none,\n"
        File.write(File.join(data_dir, "reconciliation_output.csv"), csv)
      end

      it "renders without metrics" do
        get "/summary/#{pipeline_id}"
        expect(last_response).to be_ok
        # No actionable rows → @metrics is nil, no grade displayed
        body = last_response.body
        expect(body).not_to include("overall_grade")
      end
    end

    context "with missing product_type_name" do
      before do
        csv = "id,name,row_action,updated_fields\n1,Mystery Product,update,description\n"
        File.write(File.join(data_dir, "reconciliation_output.csv"), csv)
      end

      it "defaults to Unknown type" do
        get "/summary/#{pipeline_id}"
        expect(last_response).to be_ok
        expect(last_response.body).to include("Unknown")
      end
    end

    context "with BOM-encoded output" do
      before do
        csv = "\xEF\xBB\xBFid,name,product_type_name,row_action,updated_fields\n1,Test,Flower,update,description\n"
        File.write(File.join(data_dir, "reconciliation_output.csv"), csv, mode: "wb")
      end

      it "strips BOM and parses correctly" do
        get "/summary/#{pipeline_id}"
        expect(last_response).to be_ok
        expect(last_response.body).to include("Flower")
      end
    end

    it "returns 404 for unknown session" do
      get "/summary/nonexistent"
      expect(last_response.status).to eq(404)
    end
  end

  describe "POST /upload with no source" do
    it "returns 400" do
      txt = Tempfile.new(["test", ".xlsx"])
      txt.write("hello")
      txt.rewind

      post "/upload",
        file: Rack::Test::UploadedFile.new(txt.path, "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet")

      expect(last_response.status).to eq(400)
      expect(last_response.body).to include("No source selected")
      txt.close!
    end
  end

  describe "GET /preview/:id" do
    let(:pipeline_id) { "prevtest1" }
    let(:session_dir) { File.join(File.dirname(__FILE__), "../tmp/sessions") }

    before { FileUtils.mkdir_p(session_dir) }

    context "with flattened data only" do
      before do
        pipeline = {
          "id" => pipeline_id,
          "source" => "iheartjane",
          "filename" => "test.xlsx",
          "rows" => [{ "Brand" => "Test", "_product_category" => "Flower" }],
          "columns" => ["Brand", "_product_category"],
          "stats" => { "Flower" => { "total" => 5, "kept" => 1 } },
        }
        File.write(File.join(session_dir, "#{pipeline_id}.json"), JSON.pretty_generate(pipeline))
      end

      it "shows stats and POSaBIT upload form" do
        get "/preview/#{pipeline_id}"

        expect(last_response).to be_ok
        expect(last_response.body).to include("Products Extracted")
        expect(last_response.body).to include("Flower")
        expect(last_response.body).to include("POSaBIT")
        expect(last_response.body).to include("upload-posabit")
      end
    end

    context "with both datasets loaded" do
      before do
        pipeline = {
          "id" => pipeline_id,
          "source" => "iheartjane",
          "filename" => "test.xlsx",
          "rows" => [{ "Brand" => "Test" }],
          "columns" => ["Brand"],
          "stats" => { "Flower" => { "total" => 1, "kept" => 1 } },
          "has_posabit" => true,
          "posabit_row_count" => 1,
          "posabit_brands" => ["Phat Panda"],
          "posabit_types" => ["Flower"],
          "posabit_columns" => ["id", "brand_name", "product_type_name"],
          "posabit_filename" => "export.csv",
        }
        File.write(File.join(session_dir, "#{pipeline_id}.json"), JSON.pretty_generate(pipeline))
      end

      it "shows context download button" do
        get "/preview/#{pipeline_id}"

        expect(last_response).to be_ok
        expect(last_response.body).to include("Download Context File")
        expect(last_response.body).to include("POSaBIT Catalog Loaded")
        expect(last_response.body).not_to include("upload-posabit")
      end
    end
  end
end
