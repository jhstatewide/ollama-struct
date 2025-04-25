# File: spec/ollama/struct_spec.rb

require 'spec_helper'
require 'webmock/rspec'

RSpec.describe Ollama::Struct do
  before { WebMock.disable_net_connect! }
  after { WebMock.allow_net_connect! }

  let(:client) { described_class.new(model: 'llama2') }
  let(:base_url) { 'http://localhost:11434/api/chat' }

  describe '#initialize' do
    it 'sets default host and port' do
      expect(client.host).to eq('localhost')
      expect(client.port).to eq(11_434)
    end

    it 'allows custom host and port' do
      custom_client = described_class.new(model: 'llama2', host: 'example.com', port: 8000)
      expect(custom_client.host).to eq('example.com')
      expect(custom_client.port).to eq(8000)
    end
  end

  describe '#chat' do
    let(:messages) { [{ role: 'user', content: 'Tell me about Canada.' }] }

    context 'with simple object schema' do
      let(:format) do
        Ollama::Schema.object(
          properties: {
            name: Ollama::Schema.string,
            capital: Ollama::Schema.string,
            population: Ollama::Schema.integer
          },
          required: ['name', 'capital']
        )
      end

      let(:api_response) do
        {
          message: {
            role: 'assistant',
            content: '{"name":"Canada","capital":"Ottawa","population":38000000}'
          },
          done: true
        }
      end

      before do
        stub_request(:post, base_url)
          .with(
            body: hash_including({
                                   model: 'llama2',
                                   messages: messages,
                                   format: format
                                 })
          )
          .to_return(status: 200, body: api_response.to_json)
      end

      it 'parses structured JSON response' do
        result = client.chat(messages: messages, format: format)
        expect(result).to include(
                            'name' => 'Canada',
                            'capital' => 'Ottawa',
                            'population' => 38000000
                          )
      end
    end

    context 'with array schema' do
      let(:format) do
        Ollama::Schema.array(
          Ollama::Schema.object(
            properties: { city: Ollama::Schema.string },
            required: ['city']
          )
        )
      end

      let(:api_response) do
        {
          message: {
            role: 'assistant',
            content: '[{"city":"Toronto"},{"city":"Vancouver"}]'
          },
          done: true
        }
      end

      before do
        stub_request(:post, base_url)
          .to_return(status: 200, body: api_response.to_json)
      end

      it 'handles array responses' do
        result = client.chat(messages: messages, format: format)
        expect(result).to eq([
                               { 'city' => 'Toronto' },
                               { 'city' => 'Vancouver' }
                             ])
      end
    end

    context 'with invalid JSON response' do
      let(:format) { Ollama::Schema.string }
      let(:api_response) do
        {
          message: {
            role: 'assistant',
            content: 'Invalid JSON'
          },
          done: true
        }
      end

      before do
        stub_request(:post, base_url)
          .to_return(status: 200, body: api_response.to_json)
      end

      it 'returns raw content on JSON parse error' do
        result = client.chat(messages: messages, format: format)
        expect(result).to eq('Invalid JSON')
      end
    end

    context 'with additional options' do
      let(:format) { Ollama::Schema.string }
      let(:options) { { temperature: 0.7, top_p: 0.9 } }

      before do
        stub_request(:post, base_url)
          .with(
            body: hash_including({
                                   temperature: 0.7,
                                   top_p: 0.9
                                 })
          )
          .to_return(status: 200, body: { message: { content: 'Response' } }.to_json)
      end

      it 'includes additional options in request' do
        client.chat(messages: messages, format: format, options: options)
        expect(WebMock).to have_requested(:post, base_url)
                             .with(body: hash_including(options))
      end
    end
  end

  describe 'schema validation' do
    let(:messages) { [{ role: 'user', content: 'Tell me about Canada.' }] }
    
    context 'with object schemas' do
      let(:schema) do
        Ollama::Schema.object(
          properties: {
            name: Ollama::Schema.string,
            description: Ollama::Schema.string
          },
          required: ['name', 'description']
        )
      end

      it 'validates required fields' do
        missing_fields = []
        valid = client.send(:validate_schema_completeness, 
                            { 'name' => 'Canada' }, 
                            schema, 
                            missing_fields)
        
        expect(valid).to be false
        expect(missing_fields).to include('description')
      end

      it 'accepts valid data' do
        missing_fields = []
        valid = client.send(:validate_schema_completeness,
                            { 'name' => 'Canada', 'description' => 'A country' },
                            schema,
                            missing_fields)
        
        expect(valid).to be true
        expect(missing_fields).to be_empty
      end
    end

    context 'with array schemas' do
      let(:array_schema) do
        Ollama::Schema.array(
          Ollama::Schema.object(
            properties: { city: Ollama::Schema.string },
            required: ['city']
          ),
          exact: 3
        )
      end

      it 'validates exact item count' do
        missing_fields = []
        valid = client.send(:validate_schema_completeness,
                            [{ 'city' => 'Toronto' }, { 'city' => 'Vancouver' }],
                            array_schema,
                            missing_fields)
        
        expect(valid).to be false
        expect(missing_fields.first).to include('requires exactly 3 items')
      end
    end
  end

  describe 'default value handling' do
    let(:messages) { [{ role: 'user', content: 'Tell me about Canada.' }] }
    let(:incomplete_response) { { 'name' => 'Canada' } }
    
    describe 'object defaults' do
      let(:object_schema) do
        Ollama::Schema.object(
          properties: {
            name: Ollama::Schema.string,
            description: Ollama::Schema.string
          },
          required: ['name', 'description']
        )
      end

      it 'applies simple object defaults' do
        result = client.send(:apply_defaults, 
                             incomplete_response, 
                             object_schema, 
                             { 'description' => 'Default description' })
        
        expect(result['name']).to eq('Canada')
        expect(result['description']).to eq('Default description')
      end

      it 'applies nested object defaults' do
        nested_schema = Ollama::Schema.object(
          properties: {
            name: Ollama::Schema.string,
            details: Ollama::Schema.object(
              properties: { capital: Ollama::Schema.string },
              required: ['capital']
            )
          },
          required: ['name', 'details']
        )

        result = client.send(:apply_defaults,
                             { 'name' => 'Canada' },
                             nested_schema,
                             { 'details' => { 'capital' => 'Ottawa' } })
        
        expect(result['details']['capital']).to eq('Ottawa')
      end
    end

    describe 'array defaults' do
      let(:array_schema) do
        Ollama::Schema.array(
          Ollama::Schema.object(
            properties: { city: Ollama::Schema.string },
            required: ['city']
          ),
          exact: 3
        )
      end

      it 'fills missing array items with positional defaults' do
        # Test with incomplete array and positional defaults
        incomplete_array = [{ 'city' => 'Toronto' }, { 'city' => 'Vancouver' }]
        
        # Define positional defaults - nil for existing items, specific default for missing item
        positional_defaults = [
          nil,                      # Skip first item (already exists)
          nil,                      # Skip second item (already exists)
          { 'city' => 'Montreal' }  # Default for third item
        ]
        
        result = client.send(:apply_defaults, incomplete_array, array_schema, positional_defaults)
        
        # Verify we get exactly 3 items with the correct values
        expect(result.length).to eq(3)
        expect(result[0]['city']).to eq('Toronto')
        expect(result[1]['city']).to eq('Vancouver')
        expect(result[2]['city']).to eq('Montreal')
      end
      
      it 'fills missing array items using template default' do
        # Test with incomplete array and a single template default
        incomplete_array = [{ 'city' => 'Toronto' }]
        template_default = [{ 'city' => 'Default City' }]
        
        result = client.send(:apply_defaults, incomplete_array, array_schema, template_default)
        
        # Verify we get exactly 3 items, with the template used for missing items
        expect(result.length).to eq(3)
        expect(result[0]['city']).to eq('Toronto')
        expect(result[1]['city']).to eq('Default City')
        expect(result[2]['city']).to eq('Default City')
      end
      
      it 'creates a new array with defaults if none exists' do
        # Test with nil input and a single default template
        result = client.send(:apply_defaults, nil, array_schema, [{ 'city' => 'Default City' }])
        
        # Verify we get exactly 3 items, all using the template
        expect(result.length).to eq(3)
        expect(result[0]['city']).to eq('Default City')
        expect(result[1]['city']).to eq('Default City')
        expect(result[2]['city']).to eq('Default City')
      end
    end
  end

  describe 'retry and complete response handling' do
    let(:messages) { [{ role: 'user', content: 'Tell me about Canada.' }] }
    let(:schema) do
      Ollama::Schema.object(
        properties: {
          name: Ollama::Schema.string,
          description: Ollama::Schema.string,
          details: Ollama::Schema.object(
            properties: {
              capital: Ollama::Schema.string,
              population: Ollama::Schema.integer
            },
            required: ['capital']
          )
        },
        required: ['name', 'description']
      )
    end

    context 'with incomplete response' do
      let(:incomplete_response) do
        {
          message: {
            role: 'assistant',
            content: '{"name":"Canada"}'
          },
          done: true
        }
      end

      let(:complete_response) do
        {
          message: {
            role: 'assistant',
            content: '{"name":"Canada","description":"A country in North America","details":{"capital":"Ottawa","population":38000000}}'
          },
          done: true
        }
      end

      before do
        # First attempt returns incomplete data
        stub_request(:post, base_url)
          .with(body: hash_including({ 
            "model" => "llama2",
            "messages" => [{ "role" => "user", "content" => "Tell me about Canada." }],
            "temperature" => 0.7
          }))
          .to_return(status: 200, body: incomplete_response.to_json)
        
        # Second attempt (retry) with incremented temperature
        stub_request(:post, base_url)
          .with(body: hash_including({ 
            "model" => "llama2",
            "temperature" => 0.8
          }))
          .to_return(status: 200, body: complete_response.to_json)
          
        # Stub for targeted retry with specific request content
        stub_request(:post, base_url)
          .with(body: ->(body) {
            body_hash = JSON.parse(body)
            messages = body_hash["messages"]
            messages.length == 2 && 
            messages[0]["content"] == "Tell me about Canada." &&
            messages[1]["content"].include?("missing some required information")
          })
          .to_return(status: 200, body: complete_response.to_json)
      end

      it 'retries to get complete data' do
        result = client.chat(
          messages: messages, 
          format: schema, 
          options: { 
            max_retries: 1, 
            ensure_complete: true,
            temperature: 0.7
          }
        )
        
        expect(result['name']).to eq('Canada')
        expect(result['description']).to eq('A country in North America')
        expect(result['details']['capital']).to eq('Ottawa')
      end
    end

    context 'with defaults when data is incomplete' do
      let(:incomplete_response) do
        {
          message: {
            role: 'assistant',
            content: '{"name":"Canada"}'
          },
          done: true
        }
      end

      before do
        stub_request(:post, base_url)
          .with(body: hash_including({
            "model" => "llama2",
            "messages" => [{ "role" => "user", "content" => "Tell me about Canada." }]
          }))
          .to_return(status: 200, body: incomplete_response.to_json)
      end

      it 'applies defaults for missing fields' do
        result = client.chat(
          messages: messages, 
          format: schema, 
          options: { 
            ensure_complete: true,
            defaults: {
              'description' => 'Default description',
              'details' => {
                'capital' => 'Default Capital',
                'population' => 1000
              }
            }
          }
        )
        
        expect(result['name']).to eq('Canada')
        expect(result['description']).to eq('Default description')
        expect(result).to have_key('details')
        expect(result['details']).to be_a(Hash)
        expect(result['details']['capital']).to eq('Default Capital')
        expect(result['details']['population']).to eq(1000)
      end
    end
  end

  describe 'strict mode' do
    let(:messages) { [{ role: 'user', content: 'Tell me about Canada.' }] }
    let(:schema) do
      Ollama::Schema.object(
        properties: {
          name: Ollama::Schema.string,
          description: Ollama::Schema.string,
          capital: Ollama::Schema.string
        },
        required: ['name', 'description', 'capital']
      )
    end
    
    let(:incomplete_response) do
      {
        message: {
          role: 'assistant',
          content: '{"name":"Canada","description":"A beautiful country"}'
        },
        done: true
      }
    end
    
    before do
      stub_request(:post, base_url)
        .to_return(status: 200, body: incomplete_response.to_json)
    end
    
    it 'raises IncompleteResponseError in strict mode' do
      expect {
        client.chat(
          messages: messages, 
          format: schema, 
          options: { 
            ensure_complete: true,
            strict: true
          }
        )
      }.to raise_error(Ollama::IncompleteResponseError)
    end
    
    it 'includes missing fields in the exception' do
      begin
        client.chat(
          messages: messages, 
          format: schema, 
          options: { 
            ensure_complete: true,
            strict: true
          }
        )
      rescue Ollama::IncompleteResponseError => e
        expect(e.missing_fields).to include('capital')
        expect(e.partial_response).to include('name' => 'Canada')
      end
    end
    
    it 'applies defaults in non-strict mode' do
      result = client.chat(
        messages: messages, 
        format: schema, 
        options: { 
          ensure_complete: true,
          strict: false,
          defaults: {
            'capital' => 'Ottawa'
          }
        }
      )
      
      expect(result['capital']).to eq('Ottawa')
    end
  end

  describe 'error handling' do
    let(:messages) { [{ role: 'user', content: 'Tell me about Canada.' }] }
    let(:format) { Ollama::Schema.string }

    context 'when connection fails' do
      before do
        stub_request(:post, base_url).to_raise(Errno::ECONNREFUSED)
      end

      it 'raises ConnectionError' do
        expect { client.chat(messages: messages, format: format) }.to raise_error(Ollama::ConnectionError)
      end
    end

    context 'when model is not found' do
      before do
        stub_request(:post, base_url)
          .to_return(status: 404, body: { error: "model 'llama2' not found" }.to_json)
      end

      it 'raises ModelNotFoundError' do
        expect { client.chat(messages: messages, format: format) }.to raise_error(Ollama::ModelNotFoundError)
      end
    end

    context 'when API returns an error' do
      before do
        stub_request(:post, base_url)
          .to_return(status: 400, body: { error: "bad request" }.to_json)
      end

      it 'raises APIError with status code' do
        begin
          client.chat(messages: messages, format: format)
        rescue Ollama::APIError => e
          expect(e.status_code).to eq(400)
          expect(e.message).to include("bad request")
        end
      end
    end
  end
end
