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
end