# frozen_string_literal: true

require 'spec_helper'
require 'legion/mcp'

RSpec.describe Legion::MCP::Tools::PromptList do
  let(:prompts) do
    [
      { name: 'system-prompt', description: 'System context', latest_version: 2, updated_at: Time.now },
      { name: 'user-query', description: nil, latest_version: 1, updated_at: Time.now }
    ]
  end

  describe '.call' do
    context 'when lex-prompt is not loaded' do
      before do
        allow(described_class).to receive(:extension_loaded?).with('prompt').and_return(false)
      end

      it 'returns an error response' do
        response = described_class.call
        expect(response).to be_a(MCP::Tool::Response)
        expect(response.error?).to be true
      end

      it 'error message mentions lex-prompt' do
        response = described_class.call
        data = Legion::JSON.load(response.content.first[:text])
        expect(data[:error]).to include('lex-prompt')
      end
    end

    context 'when lex-prompt is loaded' do
      let(:mock_client) { double('client', list_prompts: prompts) }

      before do
        allow(described_class).to receive(:extension_loaded?).with('prompt').and_return(true)
        stub_const('Legion::Extensions::Prompt::Client', Class.new)
        allow(Legion::Extensions::Prompt::Client).to receive(:new).and_return(mock_client)
        allow(described_class).to receive(:require).with('legion/extensions/prompt/client')
        allow(described_class).to receive(:db).and_return(nil)
      end

      it 'returns a successful response' do
        response = described_class.call
        expect(response).to be_a(MCP::Tool::Response)
        expect(response.error?).to be false
      end

      it 'calls list_prompts on the client' do
        expect(mock_client).to receive(:list_prompts)
        described_class.call
      end

      it 'response contains prompt data' do
        response = described_class.call
        data = Legion::JSON.load(response.content.first[:text])
        expect(data).to be_an(Array)
        expect(data.first[:name]).to eq('system-prompt')
      end
    end

    context 'when an error occurs' do
      before do
        allow(described_class).to receive(:extension_loaded?).with('prompt').and_return(true)
        allow(described_class).to receive(:require).with('legion/extensions/prompt/client')
        allow(described_class).to receive(:db).and_return(nil)
        stub_const('Legion::Extensions::Prompt::Client', Class.new)
        allow(Legion::Extensions::Prompt::Client).to receive(:new).and_raise(StandardError, 'db error')
      end

      it 'returns an error response' do
        response = described_class.call
        expect(response.error?).to be true
        data = Legion::JSON.load(response.content.first[:text])
        expect(data[:error]).to include('db error')
      end
    end
  end
end
