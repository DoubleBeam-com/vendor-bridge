require "sinatra/base"
require "sinatra/json"
require "securerandom"
require "json"
require "csv"
require_relative "lib/vendor_bridge/adapters/iheartjane_v1"

module VendorBridge
  class App < Sinatra::Base
    set :views, File.join(__dir__, "views")
    set :public_folder, File.join(__dir__, "public")
    set :tmp_dir, File.join(__dir__, "tmp")

    enable :sessions
    set :session_secret, ENV.fetch("SESSION_SECRET") { SecureRandom.hex(32) }

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

      id = SecureRandom.hex(8)
      ext = File.extname(file[:filename])
      upload_path = File.join(uploads_dir, "#{id}#{ext}")
      File.write(upload_path, file[:tempfile].read, mode: "wb")

      adapter_class = Adapters::Registry.fetch(source)
      adapter = adapter_class.new
      result = adapter.flatten(upload_path)

      pipeline = {
        "id" => id,
        "step" => "preview",
        "source" => source,
        "filename" => file[:filename],
        "upload_path" => upload_path,
        "rows" => result[:rows],
        "columns" => result[:columns],
        "stats" => result[:stats],
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
  end
end
