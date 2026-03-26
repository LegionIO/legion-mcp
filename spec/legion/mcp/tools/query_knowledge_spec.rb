# frozen_string_literal: true

require 'spec_helper'
require 'legion/mcp'

RSpec.describe Legion::MCP::Tools::QueryKnowledge do
  describe '.tool_name' do
    it 'is legion.query_knowledge' do
      expect(described_class.tool_name).to eq('legion.query_knowledge')
    end
  end

  describe '.call' do
    context 'when lex-knowledge is not available' do
      before do
        allow(described_class).to receive(:knowledge_available?).and_return(false)
      end

      it 'returns an error response' do
        response = described_class.call(question: 'what is legion?')
        expect(response).to be_a(MCP::Tool::Response)
        expect(response.error?).to be true
      end

      it 'error message mentions lex-knowledge' do
        response = described_class.call(question: 'what is legion?')
        data = Legion::JSON.load(response.content.first[:text])
        expect(data[:error]).to include('lex-knowledge')
      end
    end

    context 'when lex-knowledge is available' do
      let(:query_result) { { answer: 'Legion is an async job engine.', sources: [] } }

      before do
        allow(described_class).to receive(:knowledge_available?).and_return(true)
        stub_const('Legion::Extensions::Knowledge::Runners::Query', Class.new)
        allow(Legion::Extensions::Knowledge::Runners::Query).to receive(:query).and_return(query_result)
      end

      it 'returns a successful MCP::Tool::Response' do
        response = described_class.call(question: 'what is legion?')
        expect(response).to be_a(MCP::Tool::Response)
        expect(response.error?).to be false
      end

      it 'passes question with default top_k and synthesize' do
        expect(Legion::Extensions::Knowledge::Runners::Query).to receive(:query).with(
          question:   'what is legion?',
          top_k:      5,
          synthesize: true
        ).and_return(query_result)
        described_class.call(question: 'what is legion?')
      end

      it 'passes all kwargs through to Runners::Query.query' do
        expect(Legion::Extensions::Knowledge::Runners::Query).to receive(:query).with(
          question:   'foo',
          top_k:      3,
          synthesize: false
        ).and_return(query_result)
        described_class.call(question: 'foo', top_k: 3, synthesize: false)
      end

      it 'response content contains JSON text with result data' do
        response = described_class.call(question: 'what is legion?')
        data = Legion::JSON.load(response.content.first[:text])
        expect(data[:answer]).to eq('Legion is an async job engine.')
      end

      it 'returns error response when Runners::Query.query raises StandardError' do
        allow(Legion::Extensions::Knowledge::Runners::Query).to receive(:query).and_raise(StandardError, 'query failed')
        response = described_class.call(question: 'what is legion?')
        expect(response).to be_a(MCP::Tool::Response)
        expect(response.error?).to be true
        data = Legion::JSON.load(response.content.first[:text])
        expect(data[:error]).to include('query failed')
      end
    end
  end
end
