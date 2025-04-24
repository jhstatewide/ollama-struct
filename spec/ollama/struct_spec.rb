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

  describe 'validation and default handling' do
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

      before do
        # First attempt returns incomplete data
        stub_request(:post, base_url)
          .with(body: hash_including({ temperature: 0.7 }))
          .to_return(status: 200, body: incomplete_response.to_json)
        
        # Second attempt (retry) returns more complete data
        stub_request(:post, base_url)
          .with(body: hash_including({ temperature: 0.8 }))
          .to_return(status: 200, body: {
            message: {
              role: 'assistant',
              content: '{"name":"Canada","description":"A country in North America","details":{"capital":"Ottawa","population":38000000}}'
            },
            done: true
          }.to_json)
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
        expect(result['details']['capital']).to eq('Default Capital')
        expect(result['details']['population']).to eq(1000)
      end
    end
  end

  describe 'array constraints' do
    let(:messages) { [{ role: 'user', content: 'List some cities in Canada.' }] }
    
    context 'with exact item count' do
      let(:schema) do
        Ollama::Schema.array(
          Ollama::Schema.object(
            properties: { city: Ollama::Schema.string },
            required: ['city']
          ),
          exact: 3
        )
      end
      
      let(:incomplete_response) do
        {
          message: {
            role: 'assistant',
            content: '[{"city":"Toronto"},{"city":"Vancouver"}]'
          },
          done: true
        }
      end
      
      let(:complete_response) do
        {
          message: {
            role: 'assistant',
            content: '[{"city":"Toronto"},{"city":"Vancouver"},{"city":"Montreal"}]'
          },
          done: true
        }
      end
      
      before do
        # First attempt returns incomplete data (only 2 cities)
        stub_request(:post, base_url)
          .with(body: hash_including({ temperature: 0.7 }))
          .to_return(status: 200, body: incomplete_response.to_json)
        
        # Second attempt (retry) returns correct number of cities
        stub_request(:post, base_url)
          .with(body: hash_including({ temperature: 0.8 }))
          .to_return(status: 200, body: complete_response.to_json)
      end
      
      it 'retries until exact number of items is received' do
        result = client.chat(
          messages: messages, 
          format: schema, 
          options: { 
            max_retries: 1, 
            ensure_complete: true,
            temperature: 0.7
          }
        )
        
        expect(result.length).to eq(3)
        expect(result.map { |item| item['city'] }).to include('Toronto', 'Vancouver', 'Montreal')
      end
      
      it 'generates missing items with defaults if needed' do
        # Stub to always return incomplete
        stub_request(:post, base_url)
          .to_return(status: 200, body: incomplete_response.to_json)
          
        result = client.chat(
          messages: messages, 
          format: schema, 
          options: { 
            ensure_complete: true,
            defaults: [
              { 'city' => 'Default City' }
            ]
          }
        )
        
        expect(result.length).to eq(3)
        expect(result[2]['city']).to eq('Default City')
      end
    end
    
    context 'with min/max item count' do
      let(:schema) do
        Ollama::Schema.array(
          Ollama::Schema.object(
            properties: { city: Ollama::Schema.string },
            required: ['city']
          ),
          min: 2,
          max: 4
        )
      end
      
      let(:too_few_response) do
        {
          message: {
            role: 'assistant',
            content: '[{"city":"Toronto"}]'
          },
          done: true
        }
      end
      
      let(:valid_response) do
        {
          message: {
            role: 'assistant',
            content: '[{"city":"Toronto"},{"city":"Vancouver"},{"city":"Montreal"}]'
          },
          done: true
        }
      end
      
      let(:too_many_response) do
        {
          message: {
            role: 'assistant',
            content: '[{"city":"Toronto"},{"city":"Vancouver"},{"city":"Montreal"},{"city":"Calgary"},{"city":"Ottawa"}]'
          },
          done: true
        }
      end
      
      it 'validates minimum item count' do
        stub_request(:post, base_url)
          .to_return(status: 200, body: too_few_response.to_json)
          
        result = client.chat(
          messages: messages, 
          format: schema, 
          options: { 
            ensure_complete: true,
            defaults: [{ 'city' => 'Default City' }]
          }
        )
        
        expect(result.length).to be >= 2
      end
      
      it 'accepts valid item count in range' do
        stub_request(:post, base_url)
          .to_return(status: 200, body: valid_response.to_json)
          
        result = client.chat(
          messages: messages, 
          format: schema, 
          options: { ensure_complete: true }
        )
        
        expect(result.length).to eq(3)
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