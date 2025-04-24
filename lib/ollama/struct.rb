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
  class IncompleteResponseError < Error
    attr_reader :missing_fields, :partial_response
    
    def initialize(message, missing_fields = [], partial_response = nil)
      @missing_fields = missing_fields
      @partial_response = partial_response
      super(message)
    end
  end
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
    # @option options [Boolean] :strict (false) Raise exception instead of using defaults for incomplete data
    # @option options [Boolean] :targeted_retries (true) Use targeted prompts about missing fields when retrying
    def chat(messages:, format:, stream: false, options: {})
      # Extract retry-specific options
      max_retries = options.delete(:max_retries) || 0
      ensure_complete = options.delete(:ensure_complete) || false
      defaults = options.delete(:defaults) || {}
      strict = options.delete(:strict) || false
      targeted_retries = options.key?(:targeted_retries) ? options.delete(:targeted_retries) : true
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
                missing_fields = []
                valid = validate_schema_completeness(parsed_content, format, missing_fields)
                
                if valid
                  return parsed_content
                elsif retries_left > 0
                  retries_left -= 1
                  current_temperature += 0.1
                  
                  # Add targeted guidance for the retry if enabled
                  if targeted_retries && !missing_fields.empty?
                    retry_prompt = generate_targeted_prompt(missing_fields, format)
                    current_messages << {
                      role: 'user',
                      content: retry_prompt
                    }
                  else
                    # Generic retry prompt
                    current_messages << {
                      role: 'user',
                      content: "Please try again with more complete information for all required fields."
                    }
                  end
                  next
                else
                  # If strict mode is enabled, raise an exception instead of using defaults
                  if strict
                    error_message = "Incomplete response from model after #{max_retries} retries."
                    error_message += " Missing fields: #{missing_fields.join(', ')}" unless missing_fields.empty?
                    raise IncompleteResponseError.new(error_message, missing_fields, parsed_content)
                  end
                  
                  # Apply defaults if retries are exhausted and not in strict mode
                  return apply_defaults(parsed_content, format, defaults)
                end
              end
              
              return parsed_content
            rescue JSON::ParserError => e
              if retries_left > 0 && ensure_complete
                retries_left -= 1
                current_temperature += 0.05
                current_messages << {
                  role: 'user',
                  content: "Your response couldn't be parsed as valid JSON. Please provide a properly formatted response."
                }
                next
              elsif strict && ensure_complete
                raise IncompleteResponseError.new("Failed to parse JSON response: #{e.message}", [], response['message']['content'])
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

    # Generate a targeted prompt to help the model fix specific missing fields
    def generate_targeted_prompt(missing_fields, schema)
      prompt = "Your response is missing some required information. Please provide the following details:\n\n"
      
      missing_fields.each do |field_path|
        prompt += "- #{field_path}\n"
      end
      
      prompt += "\nPlease include these details in your next response while keeping all the information you've already provided."
    end

    # Recursively validate schema completeness, now tracking missing fields
    def validate_schema_completeness(data, schema, missing_fields = [], path = "")
      case schema[:type]
      when 'object'
        return false unless data.is_a?(Hash)
        
        valid = true
        
        # Check required fields
        if schema[:required]
          schema[:required].each do |field|
            field_path = path.empty? ? field : "#{path}.#{field}"
            
            if !data.key?(field) || data[field].nil?
              missing_fields << field_path
              valid = false
            elsif schema[:properties] && schema[:properties][field]
              # Recursively validate the required field's content
              field_valid = validate_schema_completeness(
                data[field], 
                schema[:properties][field], 
                missing_fields, 
                field_path
              )
              valid = false unless field_valid
            elsif data[field].is_a?(String) && data[field].strip.empty?
              # Specifically check for empty strings
              missing_fields << field_path
              valid = false
            end
          end
        end
        
        # Check properties if they exist in the data
        if schema[:properties]
          schema[:properties].each do |prop_name, prop_schema|
            field_path = path.empty? ? prop_name : "#{path}.#{prop_name}"
            
            if data.key?(prop_name) && !data[prop_name].nil?
              # Only validate fields that actually exist in the data
              field_valid = validate_schema_completeness(
                data[prop_name], 
                prop_schema, 
                missing_fields, 
                field_path
              )
              valid = false unless field_valid
            end
          end
        end
        
        valid
      when 'array'
        return false unless data.is_a?(Array)
        
        valid = true
        
        # Check array length constraints if specified
        if schema[:minItems] && data.length < schema[:minItems]
          missing_fields << "#{path} (requires at least #{schema[:minItems]} items, has #{data.length})"
          valid = false
        end
        
        if schema[:maxItems] && data.length > schema[:maxItems]
          missing_fields << "#{path} (exceeds maximum of #{schema[:maxItems]} items, has #{data.length})"
          valid = false
        end
        
        if schema[:exactItems] && data.length != schema[:exactItems]
          missing_fields << "#{path} (requires exactly #{schema[:exactItems]} items, has #{data.length})"
          valid = false
        end
        
        return valid if data.empty?
        
        # Check items schema if specified
        if schema[:items]
          data.each_with_index do |item, idx|
            item_path = "#{path}[#{idx}]"
            item_valid = validate_schema_completeness(item, schema[:items], missing_fields, item_path)
            valid = false unless item_valid
          end
        end
        
        valid
      when 'string'
        if !data.is_a?(String) || data.strip.empty?
          missing_fields << "#{path} (empty or not a string)"
          return false
        end
        true
      when 'number', 'integer'
        if !data.is_a?(Numeric)
          missing_fields << "#{path} (not a number)"
          return false
        end
        true
      when 'boolean'
        if data != true && data != false
          missing_fields << "#{path} (not a boolean)"
          return false
        end
        true
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
        result_array = data.is_a?(Array) ? data : []
        
        # If array is empty or needs more items to meet constraints
        if schema[:items]
          # Determine target size based on constraints
          target_size = if schema[:exactItems]
                          schema[:exactItems]
                        elsif schema[:minItems] && result_array.length < schema[:minItems]
                          schema[:minItems]
                        elsif result_array.empty? && schema[:minItems]
                          schema[:minItems]
                        elsif result_array.empty?
                          1 # Default to 1 item if no constraints
                        else
                          result_array.length # Keep current length if sufficient
                        end
          
          # Generate additional items if needed
          while result_array.length < target_size
            default_item = if defaults.is_a?(Array) && defaults[result_array.length]
                            defaults[result_array.length]
                          elsif defaults.is_a?(Array) && !defaults.empty?
                            defaults.first
                          else
                            {}
                          end
            
            result_array << create_default_for_schema(schema[:items], default_item)
          end
          
          # Trim if too many items (for exactItems)
          if schema[:exactItems] && result_array.length > schema[:exactItems]
            result_array = result_array.take(schema[:exactItems])
          end
        end
        
        result_array
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
        result_array = []
        
        if schema[:items]
          # Create array of required size
          target_size = schema[:exactItems] || schema[:minItems] || 1
          
          # Use provided defaults if available
          if defaults.is_a?(Array) && !defaults.empty?
            # Use defaults as templates, repeating if necessary
            target_size.times do |i|
              default_template = defaults[i % defaults.length]
              result_array << create_default_for_schema(schema[:items], default_template)
            end
          else
            # Generate defaults
            target_size.times do
              result_array << create_default_for_schema(schema[:items], {})
            end
          end
        end
        
        result_array
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

    # Enhanced array method with quantity constraints
    # @param items [Hash] Schema for array items
    # @param min [Integer, nil] Minimum number of items (optional)
    # @param max [Integer, nil] Maximum number of items (optional)
    # @param exact [Integer, nil] Exact number of items (optional)
    # @return [Hash] Schema with array constraints
    def self.array(items, min: nil, max: nil, exact: nil)
      schema = {
        type: 'array',
        items: items
      }
      
      # Add constraints if specified
      schema[:minItems] = min if min
      schema[:maxItems] = max if max
      schema[:exactItems] = exact if exact
      
      # exactItems takes precedence over min/max
      if exact
        schema.delete(:minItems)
        schema.delete(:maxItems)
      end
      
      schema
    end

    # Add default values to a schema
    def self.with_defaults(schema, defaults)
      schema.merge(default: defaults)
    end
  end
end
