# frozen_string_literal: true

# File: lib/ollama/struct.rb

require 'json'
require 'uri'
require 'net/http'

module Ollama
  class Struct
    attr_reader :model, :host, :port

    def initialize(model:, host: 'localhost', port: 11_434)
      @model = model
      @host = host
      @port = port
    end

    # Main method to chat with structured output
    def chat(messages:, format:, stream: false, options: {})
      response = make_request(
        messages: messages,
        format: format,
        stream: stream,
        options: options
      )

      if response['message']
        begin
          parsed_content = JSON.parse(response['message']['content'])
          return parsed_content
        rescue JSON::ParserError
          return response['message']['content']
        end
      end

      response
    end

    private

    def make_request(messages:, format:, stream:, options:)
      uri = URI("http://#{host}:#{port}/api/chat")
      http = Net::HTTP.new(uri.host, uri.port)

      request = Net::HTTP::Post.new(uri.path)
      request['Content-Type'] = 'application/json'

      payload = {
        model: model,
        messages: messages,
        stream: stream,
        format: format
      }

      payload.merge!(options) if options.is_a?(Hash)

      request.body = payload.to_json

      response = http.request(request)
      JSON.parse(response.body)
    end
  end

  # Schema builder helper
  class Schema
    def self.object(properties:, required: [])
      {
        type: 'object',
        properties: properties,
        required: required
      }
    end

    def self.string
      { type: 'string' }
    end

    def self.integer
      { type: 'integer' }
    end

    def self.number
      { type: 'number' }
    end

    def self.boolean
      { type: 'boolean' }
    end

    def self.array(items)
      {
        type: 'array',
        items: items
      }
    end
  end
end
