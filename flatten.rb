#!/usr/bin/env ruby
require "optparse"
require "csv"
require_relative "lib/adapters/iheartjane_v1"

source = "iheartjane"
output = nil

OptionParser.new do |opts|
  opts.banner = "Usage: ruby flatten.rb [options] INPUT_FILE"
  opts.on("-s", "--source NAME", "Source adapter (default: iheartjane)") { |v| source = v }
  opts.on("-o", "--output PATH", "Output CSV path (default: input_flattened.csv)") { |v| output = v }
end.parse!

input = ARGV[0]
abort "Usage: ruby flatten.rb [options] INPUT_FILE" unless input
abort "File not found: #{input}" unless File.exist?(input)

output ||= input.sub(/\.[^.]+$/, "_flattened.csv")

adapter_class = VendorBridge::Adapters::Registry.fetch(source)
adapter = adapter_class.new

puts "Flattening #{input} with adapter '#{source}'..."
result = adapter.flatten(input)

rows = result[:rows]
columns = result[:columns]
stats = result[:stats]

puts "\nSheet stats:"
stats.each do |sheet, counts|
  puts "  #{sheet}: #{counts[:kept]} products kept (#{counts[:total]} rows scanned)"
end
puts "\nTotal products: #{rows.size}"
puts "Columns: #{columns.size}"

CSV.open(output, "wb", encoding: "UTF-8") do |csv|
  csv << columns
  rows.each do |row|
    csv << columns.map { |col| row[col] }
  end
end

puts "\nWritten to #{output}"
