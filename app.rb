require "sinatra/base"
require "sinatra/json"
require "securerandom"
require "json"
require "csv"
require_relative "lib/vendor_bridge/adapters/iheartjane_v1"
require_relative "lib/vendor_bridge/adapters/context_builder"

module VendorBridge
  class App < Sinatra::Base
    set :views, File.join(__dir__, "views")
    set :public_folder, File.join(__dir__, "public")
    set :tmp_dir, File.join(__dir__, "tmp")
    set :show_exceptions, false

    enable :sessions
    set :session_secret, ENV.fetch("SESSION_SECRET") { SecureRandom.hex(32) }

    error 400..599 do
      @error_message = body.is_a?(Array) ? body.first : body.to_s
      erb :error
    end

    helpers do
      def session_dir
        File.join(settings.tmp_dir, "sessions")
      end

      def uploads_dir
        File.join(settings.tmp_dir, "uploads")
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
      File.write(upload_path, file[:tempfile].read, mode: "wb")

      adapter_class = Adapters::Registry.fetch(source)
      adapter = adapter_class.new

      begin
        result = adapter.flatten(upload_path)
      rescue ArgumentError => e
        halt 400, e.message
      rescue StandardError => e
        halt 400, "Could not process file. Make sure you're uploading the original #{ext.upcase} export from iHeartJane, not a CSV or other format."
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

      content_type "text/csv; charset=utf-8"
      attachment "#{File.basename(pipeline["filename"], ".*")}_flattened.csv"

      CSV.generate do |csv|
        csv << columns
        rows.each { |row| csv << columns.map { |c| row[c] } }
      end
    end

    # -- Upload POSaBIT ingest-ready CSV --
    post "/upload-posabit/:id" do
      pipeline = load_pipeline(params[:id])
      halt 404, "Session not found" unless pipeline

      file = params[:posabit_file]
      halt 400, "No file uploaded" unless file

      raw = file[:tempfile].read
      # Handle BOM from Excel exports and Windows encodings
      raw = raw.b.sub(/\A\xEF\xBB\xBF/, "").force_encoding("UTF-8")
      raw = raw.encode("UTF-8", "Windows-1252", invalid: :replace, undef: :replace) unless raw.valid_encoding?
      parsed = CSV.parse(raw, headers: true)

      pipeline["posabit_rows"] = parsed.map(&:to_h)
      pipeline["posabit_columns"] = parsed.headers
      pipeline["posabit_filename"] = file[:filename]
      save_pipeline(pipeline)

      redirect "/preview/#{params[:id]}"
    end

    # -- Download context file --
    get "/context/:id" do
      pipeline = load_pipeline(params[:id])
      halt 404, "Session not found" unless pipeline
      halt 400, "POSaBIT catalog not uploaded yet" unless pipeline["posabit_rows"]

      builder = Adapters::ContextBuilder.new(pipeline)
      content = builder.generate

      content_type "text/markdown; charset=utf-8"
      attachment "reconciliation_context.md"
      content
    end
  end
end
