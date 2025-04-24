# frozen_string_literal: true

# File: lib/ollama/struct.rb

require 'json'
require 'uri'
require 'net/http'

module Ollama
  # Custom exception classes
  class Error < StandardError; end
  class ConnectionError < Error; end
  class ModelNotFoundError < Error; end
  class APIError < Error
    attr_reader :status_code, :response_body
    
    def initialize(message, status_code = nil, response_body = nil)
      @status_code = status_code
      @response_body = response_body
      super(message)
    end
  end

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

      begin
        response = http.request(request)
        
        unless response.code.to_i >= 200 && response.code.to_i < 300
          error_body = JSON.parse(response.body) rescue nil
          error_message = error_body && error_body['error'] ? error_body['error'] : "HTTP Error: #{response.code}"
          
          case response.code.to_i
          when 404
            # Check if error relates to model not found
            if error_message.include?('model') || (error_body && error_body['error'] && error_body['error'].include?('model'))
              raise ModelNotFoundError.new("Model '#{model}' not found")
            else
              raise APIError.new(error_message, response.code.to_i, response.body)
            end
          when 400..499
            raise APIError.new(error_message, response.code.to_i, response.body)
          when 500..599
            raise APIError.new("Server error: #{error_message}", response.code.to_i, response.body)
          end
        end
        
        JSON.parse(response.body)
      rescue Errno::ECONNREFUSED, Errno::ETIMEDOUT, Errno::ENETUNREACH, SocketError => e
        raise ConnectionError.new("Could not connect to Ollama server at #{host}:#{port} - #{e.message}")
      rescue JSON::ParserError => e
        raise APIError.new("Invalid response from server: #{e.message}")
      end
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
