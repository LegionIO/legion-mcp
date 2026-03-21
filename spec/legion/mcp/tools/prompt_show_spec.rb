# frozen_string_literal: true

require 'spec_helper'
require 'legion/mcp'

RSpec.describe Legion::MCP::Tools::PromptShow do
  let(:prompt_data) do
    { name: 'system-prompt', version: 2, template: 'Hello <%= name %>', model_params: {}, content_hash: 'abc123' }
  end

  describe '.call' do
    context 'when lex-prompt is not loaded' do
      before do
        allow(described_class).to receive(:extension_loaded?).with('prompt').and_return(false)
      end

      it 'returns an error response' do
        response = described_class.call(name: 'system-prompt')
        expect(response.error?).to be true
      end

      it 'error message mentions lex-prompt' do
        response = described_class.call(name: 'system-prompt')
        data = Legion::JSON.load(response.content.first[:text])
        expect(data[:error]).to include('lex-prompt')
      end
    end

    context 'when lex-prompt is loaded' do
      let(:mock_client) { double('client') }

      before do
        allow(described_class).to receive(:extension_loaded?).with('prompt').and_return(true)
        stub_const('Legion::Extensions::Prompt::Client', Class.new)
        allow(Legion::Extensions::Prompt::Client).to receive(:new).and_return(mock_client)
        allow(described_class).to receive(:require).with('legion/extensions/prompt/client')
        allow(described_class).to receive(:db).and_return(nil)
      end

      it 'returns a successful response for a found prompt' do
        allow(mock_client).to receive(:get_prompt).and_return(prompt_data)
        response = described_class.call(name: 'system-prompt')
        expect(response.error?).to be false
      end

      it 'passes name to get_prompt' do
        expect(mock_client).to receive(:get_prompt).with(name: 'system-prompt', version: nil, tag: nil).and_return(prompt_data)
        described_class.call(name: 'system-prompt')
      end

      it 'passes version when provided' do
        expect(mock_client).to receive(:get_prompt).with(name: 'system-prompt', version: 1, tag: nil).and_return(prompt_data)
        described_class.call(name: 'system-prompt', version: 1)
      end

      it 'passes tag when provided' do
        expect(mock_client).to receive(:get_prompt).with(name: 'system-prompt', version: nil, tag: 'stable').and_return(prompt_data)
        described_class.call(name: 'system-prompt', tag: 'stable')
      end

      it 'response contains prompt data' do
        allow(mock_client).to receive(:get_prompt).and_return(prompt_data)
        response = described_class.call(name: 'system-prompt')
        data = Legion::JSON.load(response.content.first[:text])
        expect(data[:name]).to eq('system-prompt')
        expect(data[:version]).to eq(2)
      end
    end
  end
end
