require "sinatra/base"
require "sinatra/json"
require "securerandom"
require "json"
require "csv"
require "fileutils"
Dir[File.join(__dir__, "lib/adapters/*.rb")].each { |f| require f }

module VendorBridge
  class App < Sinatra::Base
    set :views, File.join(__dir__, "views")
    set :public_folder, File.join(__dir__, "public")
    set :tmp_dir, File.join(__dir__, "tmp")
    set :show_exceptions, false

    enable :sessions
    set :session_secret, ENV.fetch("SESSION_SECRET") { SecureRandom.hex(32) }

    error ArgumentError do
      @error_message = env["sinatra.error"].message
      erb :error
    end

    error 400..599 do
      @error_message = body.is_a?(Array) ? body.first : body.to_s
      @error_message = "Something went wrong. Please try again." if @error_message.to_s.strip.empty?
      erb :error
    end

    helpers do
      def session_dir
        File.join(settings.tmp_dir, "sessions")
      end

      def uploads_dir
        File.join(settings.tmp_dir, "uploads")
      end

      def data_dir
        dir = File.join(settings.root, "data_files")
        FileUtils.mkdir_p(dir)
        dir
      end

      def load_pipeline(id)
        path = File.join(session_dir, "#{id}.json")
        return nil unless File.exist?(path)
        JSON.parse(File.read(path))
      end

      def save_pipeline(data)
        path = File.join(session_dir, "#{data["id"]}.json")
        File.write(path, JSON.pretty_generate(data))
      end
    end

    # -- Upload page --
    get "/" do
      @sources = Adapters::Registry.available
      erb :index
    end

    # -- Process upload --
    post "/upload" do
      file = params[:file]
      source = params[:source]

      halt 400, "No file uploaded" unless file
      halt 400, "No source selected" unless source

      ext = File.extname(file[:filename]).downcase
      unless %w[.xlsx .csv .json].include?(ext)
        halt 400, "Unsupported file type: #{ext}. Please upload an XLSX, CSV, or JSON file."
      end

      id = SecureRandom.hex(8)
      upload_path = File.join(uploads_dir, "#{id}#{ext}")
      file_bytes = file[:tempfile].read
      File.write(upload_path, file_bytes, mode: "wb")

      adapter_class = Adapters::Registry.fetch(source)
      adapter = adapter_class.new

      begin
        result = adapter.flatten(upload_path)
      rescue ArgumentError => e
        halt 400, e.message
      rescue StandardError => e
        halt 400, "Could not process file. Make sure you're uploading the original #{ext.upcase} export from #{adapter.source_label}, not a CSV or other format."
      end

      pipeline = {
        "id" => id,
        "step" => "preview",
        "source" => source,
        "source_label" => adapter.source_label,
        "filename" => file[:filename],
        "upload_path" => upload_path,
        "rows" => result[:rows],
        "columns" => result[:columns],
        "stats" => result[:stats],
        "category_mapping" => adapter.category_mapping,
        "field_mapping" => adapter.field_mapping.map { |m| m.transform_keys(&:to_s) },
      }
      save_pipeline(pipeline)

      # Save flattened CSV to data_files/ with source prefix (overwritten each run)
      flat_name = "#{source}_flattened.csv"
      CSV.open(File.join(data_dir, flat_name), "w") do |csv|
        csv << result[:columns]
        result[:rows].each { |row| csv << result[:columns].map { |c| row[c] } }
      end

      redirect "/preview/#{id}"
    end

    # -- Preview flattened data --
    get "/preview/:id" do
      @pipeline = load_pipeline(params[:id])
      halt 404, "Session not found" unless @pipeline
      erb :preview
    end

    # -- Export CSV --
    get "/export/:id" do
      pipeline = load_pipeline(params[:id])
      halt 404, "Session not found" unless pipeline

      rows = pipeline["rows"]
      columns = pipeline["columns"]
      flat_name = "#{File.basename(pipeline["filename"], ".*")}_flattened.csv"

      csv_content = CSV.generate do |csv|
        csv << columns
        rows.each { |row| csv << columns.map { |c| row[c] } }
      end

      content_type "text/csv; charset=utf-8"
      attachment flat_name
      csv_content
    end

    # -- Upload POSaBIT ingest-ready CSV --
    post "/upload-posabit/:id" do
      pipeline = load_pipeline(params[:id])
      halt 404, "Session not found" unless pipeline

      file = params[:posabit_file]
      halt 400, "No file uploaded" unless file

      raw = file[:tempfile].read

      # Save to data_files/ as fixed name (overwritten each run)
      File.write(File.join(data_dir, "posabit_data.csv"), raw, mode: "wb")

      # Handle BOM from Excel exports and Windows encodings
      raw = raw.b.sub(/\A\xEF\xBB\xBF/n, "").force_encoding("UTF-8")
      raw = raw.encode("UTF-8", "Windows-1252", invalid: :replace, undef: :replace) unless raw.valid_encoding?
      parsed = CSV.parse(raw, headers: true)

      pipeline["posabit_columns"] = parsed.headers
      pipeline["posabit_filename"] = file[:filename]
      # Don't store posabit_rows in the session — it's already in data_files/posabit_data.csv
      pipeline["has_posabit"] = true
      pipeline["posabit_row_count"] = parsed.size
      pipeline["posabit_brands"] = parsed.map { |r| r["brand_name"] }.compact.uniq.sort
      pipeline["posabit_types"] = parsed.map { |r| r["product_type_name"] }.compact.uniq.sort
      save_pipeline(pipeline)

      # Auto-generate context file
      builder = Adapters::ContextBuilder.new(pipeline)
      content = builder.generate(data_dir: data_dir)
      File.write(File.join(data_dir, "reconciliation_context.md"), content)

      redirect "/preview/#{params[:id]}"
    end

    # -- Download context file --
    get "/context/:id" do
      pipeline = load_pipeline(params[:id])
      halt 404, "Session not found" unless pipeline

      context_path = File.join(data_dir, "reconciliation_context.md")
      halt 400, "Context file not generated yet. Upload a POSaBIT catalog first." unless File.exist?(context_path)

      content_type "text/markdown; charset=utf-8"
      attachment "reconciliation_context.md"
      File.read(context_path)
    end
  end
end
