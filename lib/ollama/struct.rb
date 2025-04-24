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
  class IncompleteResponseError < Error; end
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
    # @param messages [Array] The conversation messages
    # @param format [Hash] The schema format for the response
    # @param stream [Boolean] Whether to stream the response
    # @param options [Hash] Additional options for the request
    # @option options [Integer] :max_retries (0) Maximum number of retries for incomplete data
    # @option options [Float] :temperature (0.7) Temperature for generation
    # @option options [Boolean] :ensure_complete (false) Automatically validate and fill incomplete responses
    # @option options [Hash] :defaults Default values to use for missing fields
    def chat(messages:, format:, stream: false, options: {})
      # Extract retry-specific options
      max_retries = options.delete(:max_retries) || 0
      ensure_complete = options.delete(:ensure_complete) || false
      defaults = options.delete(:defaults) || {}
      temperature = options[:temperature] || 0.7
      
      retries_left = max_retries
      current_temperature = temperature
      current_messages = messages.dup
      
      # Try to get a complete result with retries if needed
      loop do
        begin
          response = make_request(
            messages: current_messages,
            format: format,
            stream: stream,
            options: options.merge(temperature: current_temperature)
          )

          if response['message']
            begin
              parsed_content = JSON.parse(response['message']['content'])
              
              # Validate the result if ensure_complete is true
              if ensure_complete
                if validate_schema_completeness(parsed_content, format)
                  return parsed_content
                elsif retries_left > 0
                  retries_left -= 1
                  current_temperature += 0.1
                  
                  # Add guidance for the retry
                  current_messages << {
                    role: 'user',
                    content: "Please try again with more complete information for all required fields."
                  }
                  next
                else
                  # Apply defaults if retries are exhausted
                  return apply_defaults(parsed_content, format, defaults)
                end
              end
              
              return parsed_content
            rescue JSON::ParserError
              if retries_left > 0 && ensure_complete
                retries_left -= 1
                current_temperature += 0.05
                next
              end
              return response['message']['content']
            end
          end

          return response
        rescue Errno::ECONNREFUSED, Errno::ETIMEDOUT, Errno::ENETUNREACH, SocketError => e
          raise ConnectionError.new("Could not connect to Ollama server at #{host}:#{port} - #{e.message}")
        rescue JSON::ParserError => e
          if retries_left > 0 && ensure_complete
            retries_left -= 1
            current_temperature += 0.05
            next
          end
          raise APIError.new("Invalid response from server: #{e.message}")
        end
      end
    end

    private

    # Recursively validate schema completeness
    def validate_schema_completeness(data, schema)
      case schema[:type]
      when 'object'
        return false unless data.is_a?(Hash)
        
        # Check required fields
        if schema[:required]
          return false unless schema[:required].all? { |field| data.key?(field) && !data[field].nil? }
        end
        
        # Check properties if they exist in the data
        if schema[:properties]
          schema[:properties].each do |prop_name, prop_schema|
            if data.key?(prop_name)
              return false unless validate_schema_completeness(data[prop_name], prop_schema)
            end
          end
        end
        
        true
      when 'array'
        return false unless data.is_a?(Array)
        return true if data.empty?
        
        # Check items schema if specified
        if schema[:items]
          data.all? { |item| validate_schema_completeness(item, schema[:items]) }
        else
          true
        end
      when 'string'
        data.is_a?(String) && !data.strip.empty?
      when 'number', 'integer'
        data.is_a?(Numeric)
      when 'boolean'
        data == true || data == false
      else
        true # Unknown type, consider it valid
      end
    end
    
    # Apply default values to missing fields
    def apply_defaults(data, schema, defaults = {})
      case schema[:type]
      when 'object'
        data ||= {}
        
        # Handle required fields that are missing
        if schema[:required] && schema[:properties]
          schema[:required].each do |field|
            next if data.key?(field) && !data[field].nil?
            
            # Check if there's a default specified
            if defaults.key?(field)
              data[field] = defaults[field]
            elsif schema[:properties][field]
              # Create a default based on the type
              data[field] = create_default_for_schema(schema[:properties][field], defaults.dig(field) || {})
            end
          end
        end
        
        # Process all properties
        if schema[:properties]
          schema[:properties].each do |prop_name, prop_schema|
            # Skip if the property has a non-nil value
            next if data.key?(prop_name) && !data[prop_name].nil?
            
            # Use default if available, or create one
            if defaults.key?(prop_name)
              data[prop_name] = defaults[prop_name]
            else
              data[prop_name] = create_default_for_schema(prop_schema, defaults.dig(prop_name) || {})
            end
          end
        end
        
        data
      when 'array'
        return data if data.is_a?(Array) && !data.empty?
        
        # Create a default array with one item
        if schema[:items] && defaults.is_a?(Array) && !defaults.empty?
          defaults
        elsif schema[:items]
          [create_default_for_schema(schema[:items], defaults.is_a?(Array) ? defaults.first || {} : {})]
        else
          []
        end
      when 'string'
        return data if data.is_a?(String) && !data.strip.empty?
        defaults.is_a?(String) ? defaults : "Default value"
      when 'number', 'integer'
        return data if data.is_a?(Numeric)
        defaults.is_a?(Numeric) ? defaults : (schema[:type] == 'integer' ? 0 : 0.0)
      when 'boolean'
        return data if data == true || data == false
        defaults.is_a?(TrueClass) || defaults.is_a?(FalseClass) ? defaults : false
      else
        data || defaults
      end
    end
    
    # Create a default value for a given schema
    def create_default_for_schema(schema, defaults = {})
      case schema[:type]
      when 'object'
        result = {}
        if schema[:properties]
          schema[:properties].each do |prop_name, prop_schema|
            # Only create defaults for required properties
            if schema[:required]&.include?(prop_name)
              default_value = defaults.is_a?(Hash) ? defaults[prop_name] : nil
              result[prop_name] = create_default_for_schema(prop_schema, default_value || {})
            end
          end
        end
        result
      when 'array'
        if defaults.is_a?(Array) && !defaults.empty?
          defaults
        elsif schema[:items]
          [] # Empty array by default
        else
          []
        end
      when 'string'
        defaults.is_a?(String) ? defaults : "Default value"
      when 'number'
        defaults.is_a?(Numeric) ? defaults : 0.0
      when 'integer'
        defaults.is_a?(Integer) ? defaults : 0
      when 'boolean'
        defaults.is_a?(TrueClass) || defaults.is_a?(FalseClass) ? defaults : false
      else
        nil
      end
    end

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

  # Schema builder helper with extended functionality
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

    # Add default values to a schema
    def self.with_defaults(schema, defaults)
      schema.merge(default: defaults)
    end
  end
end
