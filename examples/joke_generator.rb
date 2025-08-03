#!/usr/bin/env ruby
# File: examples/joke_generator.rb

require 'bundler/inline'

gemfile do
  source 'https://rubygems.org'
  gem 'ollama-struct', path: '.'
  gem 'optparse'
end

options = {
  host: 'localhost',
  port: 11434,
  model: 'llama3.2',
  timeout: 60 # Default 60 seconds for jokes (simpler task)
}

# Parse command line arguments
OptionParser.new do |opts|
  opts.banner = "Usage: joke_generator.rb [options]"

  opts.on("-h", "--host HOST", "Ollama host (default: localhost)") do |h|
    options[:host] = h
  end

  opts.on("-p", "--port PORT", Integer, "Ollama port (default: 11434)") do |p|
    options[:port] = p
  end

  opts.on("-m", "--model MODEL", "Model to use (default: llama2)") do |m|
    options[:model] = m
  end

  opts.on("--timeout SECONDS", Integer, "Request timeout in seconds (default: 60)") do |t|
    options[:timeout] = t
  end
end.parse!

# Create client instance with timeout
client = Ollama::Struct.new(
  model: options[:model],
  host: options[:host],
  port: options[:port],
  timeout: options[:timeout]
)

# Define the joke schema
joke_schema = Ollama::Schema.object(
  properties: {
    setup: Ollama::Schema.string,
    punchline: Ollama::Schema.string,
    topic: Ollama::Schema.string
  },
  required: %w[setup punchline topic]
)

# Prepare the prompt
messages = [{
              role: 'user',
              content: 'Generate a joke with a setup and punchline. Make it funny but clean.'
            }]

puts "Generating joke using #{options[:model]} on #{options[:host]}:#{options[:port]}..."

# Make the request
begin
  result = client.chat(
    messages: messages,
    format: joke_schema,
    options: { temperature: 0.7 }
  )

  puts "\nTopic: #{result['topic']}"
  puts "\nSetup: #{result['setup']}"
  puts "Punchline: #{result['punchline']}"
rescue Ollama::ConnectionError => e
  puts "Connection Error: #{e.message}"
  exit 1
rescue Ollama::ModelNotFoundError => e
  puts "Model Error: #{e.message}"
  puts "Available models can be checked with 'ollama list' command."
  exit 1
rescue Ollama::APIError => e
  puts "API Error (#{e.status_code}): #{e.message}"
  exit 1
rescue StandardError => e
  puts "Error: #{e.message}"
  exit 1
end