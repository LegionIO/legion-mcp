# frozen_string_literal: true

require 'spec_helper'
require 'legion/mcp'

RSpec.describe Legion::MCP::Tools::EvalList do
  let(:evaluators_result) { { evaluators: %w[relevance groundedness coherence] } }

  describe '.call' do
    context 'when lex-eval is not loaded' do
      before do
        allow(described_class).to receive(:extension_loaded?).with('eval').and_return(false)
      end

      it 'returns an error response' do
        response = described_class.call
        expect(response).to be_a(MCP::Tool::Response)
        expect(response.error?).to be true
      end

      it 'error message mentions lex-eval' do
        response = described_class.call
        data = Legion::JSON.load(response.content.first[:text])
        expect(data[:error]).to include('lex-eval')
      end
    end

    context 'when lex-eval is loaded' do
      let(:mock_client) { double('client', list_evaluators: evaluators_result) }

      before do
        allow(described_class).to receive(:extension_loaded?).with('eval').and_return(true)
        stub_const('Legion::Extensions::Eval::Client', Class.new)
        allow(Legion::Extensions::Eval::Client).to receive(:new).and_return(mock_client)
        allow(described_class).to receive(:require).with('legion/extensions/eval/client')
        allow(described_class).to receive(:db).and_return(nil)
      end

      it 'returns a successful response' do
        response = described_class.call
        expect(response.error?).to be false
      end

      it 'calls list_evaluators on the client' do
        expect(mock_client).to receive(:list_evaluators)
        described_class.call
      end

      it 'response contains evaluators list' do
        response = described_class.call
        data = Legion::JSON.load(response.content.first[:text])
        expect(data).to have_key(:evaluators)
        expect(data[:evaluators]).to include('relevance')
      end
    end
  end
end
