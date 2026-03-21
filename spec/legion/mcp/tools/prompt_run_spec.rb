# frozen_string_literal: true

require 'spec_helper'
require 'legion/mcp'

RSpec.describe Legion::MCP::Tools::PromptRun do
  let(:rendered_result) { { rendered: 'Hello World', prompt_version: 2 } }

  describe '.call' do
    context 'when lex-prompt is not loaded' do
      before do
        allow(described_class).to receive(:extension_loaded?).with('prompt').and_return(false)
      end

      it 'returns an error response' do
        response = described_class.call(name: 'greeting')
        expect(response.error?).to be true
      end

      it 'error message mentions lex-prompt' do
        response = described_class.call(name: 'greeting')
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

      it 'returns a successful response' do
        allow(mock_client).to receive(:render_prompt).and_return(rendered_result)
        response = described_class.call(name: 'greeting')
        expect(response.error?).to be false
      end

      it 'passes name and empty variables by default' do
        expect(mock_client).to receive(:render_prompt)
          .with(name: 'greeting', variables: {}, version: nil)
          .and_return(rendered_result)
        described_class.call(name: 'greeting')
      end

      it 'passes variables when provided' do
        expect(mock_client).to receive(:render_prompt)
          .with(name: 'greeting', variables: { 'name' => 'World' }, version: nil)
          .and_return(rendered_result)
        described_class.call(name: 'greeting', variables: { 'name' => 'World' })
      end

      it 'passes version when provided' do
        expect(mock_client).to receive(:render_prompt)
          .with(name: 'greeting', variables: {}, version: 1)
          .and_return(rendered_result)
        described_class.call(name: 'greeting', version: 1)
      end

      it 'response contains rendered text' do
        allow(mock_client).to receive(:render_prompt).and_return(rendered_result)
        response = described_class.call(name: 'greeting', variables: { 'name' => 'World' })
        data = Legion::JSON.load(response.content.first[:text])
        expect(data[:rendered]).to eq('Hello World')
        expect(data[:prompt_version]).to eq(2)
      end
    end
  end
end
