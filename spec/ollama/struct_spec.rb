# File: spec/ollama/struct_spec.rb

require 'spec_helper'
require 'webmock/rspec'

RSpec.describe Ollama::Struct do
  before do
    WebMock.disable_net_connect!
  end

  after do
    WebMock.allow_net_connect!
  end

  let(:client) { Ollama::Struct.new(model: 'llama3.1') }

  describe '#chat' do
    let(:messages) { [{ role: 'user', content: 'Tell me about Canada.' }] }
    let(:format) do
      Ollama::Schema.object(
        properties: {
          name: Ollama::Schema.string,
          capital: Ollama::Schema.string
        },
        required: ['name']
      )
    end

    let(:api_response) do
      {
        message: {
          role: 'assistant',
          content: '{"name":"Canada","capital":"Ottawa"}'
        },
        done: true
      }
    end

    before do
      stub_request(:post, "http://localhost:11434/api/chat")
        .to_return(status: 200, body: api_response.to_json)
    end

    it 'parses the JSON response' do
      result = client.chat(messages: messages, format: format)
      expect(result).to eq({ 'name' => 'Canada', 'capital' => 'Ottawa' })
    end
  end
end