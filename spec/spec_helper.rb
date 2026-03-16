require "simplecov"
SimpleCov.start do
  add_filter "/spec/"
  add_filter "/vendor/"
  enable_coverage :branch
  minimum_coverage line: 90, branch: 80
end

require "rack/test"
require "rspec"

ENV["RACK_ENV"] = "test"

require_relative "../app"

module TestHelpers
  include Rack::Test::Methods

  def app
    VendorBridge::App
  end

  def fixture_path(name)
    File.join(__dir__, "fixtures", name)
  end
end

RSpec.configure do |config|
  config.include TestHelpers

  config.before(:each) do
    # Clean tmp between tests
    tmp = File.join(File.dirname(__dir__), "tmp")
    FileUtils.rm_rf(Dir.glob(File.join(tmp, "sessions", "*.json")))
    FileUtils.rm_rf(Dir.glob(File.join(tmp, "uploads", "*")))
  end
end
