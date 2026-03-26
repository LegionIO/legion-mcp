# frozen_string_literal: true

require 'spec_helper'
require 'legion/mcp'

RSpec.describe Legion::MCP::Tools::KnowledgeContext do
  describe '.tool_name' do
    it 'is legion.knowledge_context' do
      expect(described_class.tool_name).to eq('legion.knowledge_context')
    end
  end

  describe '.call' do
    context 'when lex-knowledge is not available' do
      before do
        allow(described_class).to receive(:knowledge_available?).and_return(false)
      end

      it 'returns an error response' do
        response = described_class.call(question: 'What is Legion?')
        expect(response).to be_a(MCP::Tool::Response)
        expect(response.error?).to be true
      end

      it 'error message mentions lex-knowledge' do
        response = described_class.call(question: 'What is Legion?')
        data = Legion::JSON.load(response.content.first[:text])
        expect(data[:error]).to include('lex-knowledge')
      end

      context 'with scope: local and Apollo::Local available' do
        let(:local_result) { { answer: 'Local only answer', sources: [] } }

        before do
          stub_const('Legion::Apollo::Local', Class.new)
          allow(Legion::Apollo::Local).to receive(:query).and_return(local_result)
          allow(described_class).to receive(:knowledge_available?).and_call_original
        end

        it 'allows local scope without lex-knowledge' do
          response = described_class.call(question: 'What gotchas exist?', scope: 'local')
          expect(response).to be_a(MCP::Tool::Response)
          expect(response.error?).to be false
        end

        it 'returns local answer from Apollo::Local' do
          response = described_class.call(question: 'What gotchas exist?', scope: 'local')
          data = Legion::JSON.load(response.content.first[:text])
          expect(data[:answer]).to eq('Local only answer')
        end
      end
    end

    context 'when lex-knowledge is available' do
      let(:query_result) do
        {
          answer:  'Legion is an async job engine.',
          sources: [{ chunk_id: 'abc', content: 'Legion runs tasks.', score: 0.9 }]
        }
      end

      before do
        stub_const('Legion::Extensions::Knowledge::Runners::Query', Class.new)
        allow(Legion::Extensions::Knowledge::Runners::Query).to receive(:query).and_return(query_result)
      end

      it 'returns a successful MCP::Tool::Response' do
        response = described_class.call(question: 'What is Legion?')
        expect(response).to be_a(MCP::Tool::Response)
        expect(response.error?).to be false
      end

      it 'passes question through to Runners::Query.query' do
        expect(Legion::Extensions::Knowledge::Runners::Query).to receive(:query).with(
          hash_including(question: 'What is Legion?')
        ).and_return(query_result)
        described_class.call(question: 'What is Legion?')
      end

      it 'defaults top_k to 5' do
        expect(Legion::Extensions::Knowledge::Runners::Query).to receive(:query).with(
          hash_including(top_k: 5)
        ).and_return(query_result)
        described_class.call(question: 'What is Legion?')
      end

      it 'passes explicit top_k through' do
        expect(Legion::Extensions::Knowledge::Runners::Query).to receive(:query).with(
          hash_including(top_k: 10)
        ).and_return(query_result)
        described_class.call(question: 'What is Legion?', top_k: 10)
      end

      it 'response content contains JSON text with result data' do
        response = described_class.call(question: 'What is Legion?')
        data = Legion::JSON.load(response.content.first[:text])
        expect(data[:answer]).to include('Legion')
      end

      it 'returns error response when Runners::Query.query raises StandardError' do
        allow(Legion::Extensions::Knowledge::Runners::Query).to receive(:query).and_raise(StandardError, 'query failed')
        response = described_class.call(question: 'What is Legion?')
        expect(response).to be_a(MCP::Tool::Response)
        expect(response.error?).to be true
        data = Legion::JSON.load(response.content.first[:text])
        expect(data[:error]).to include('query failed')
      end
    end

    context 'with scope: global' do
      let(:query_result) { { answer: 'Global answer', sources: [] } }

      before do
        stub_const('Legion::Extensions::Knowledge::Runners::Query', Class.new)
        allow(Legion::Extensions::Knowledge::Runners::Query).to receive(:query).and_return(query_result)
      end

      it 'queries via Runners::Query' do
        expect(Legion::Extensions::Knowledge::Runners::Query).to receive(:query).with(
          hash_including(question: 'How does routing work?')
        ).and_return(query_result)
        described_class.call(question: 'How does routing work?', scope: 'global')
      end

      it 'returns a successful response' do
        response = described_class.call(question: 'How does routing work?', scope: 'global')
        expect(response.error?).to be false
      end
    end

    context 'with scope: local' do
      let(:query_result) { { answer: 'Local answer', sources: [] } }

      before do
        stub_const('Legion::Extensions::Knowledge::Runners::Query', Class.new)
        allow(Legion::Extensions::Knowledge::Runners::Query).to receive(:query).and_return(query_result)
      end

      it 'returns a successful response' do
        response = described_class.call(question: 'What gotchas exist?', scope: 'local')
        expect(response).to be_a(MCP::Tool::Response)
        expect(response.error?).to be false
      end

      context 'when Legion::Apollo::Local is available' do
        let(:local_result) { { answer: 'Local store answer', sources: [] } }

        before do
          stub_const('Legion::Apollo::Local', Class.new)
          allow(Legion::Apollo::Local).to receive(:query).and_return(local_result)
        end

        it 'queries Apollo::Local instead of global runner' do
          expect(Legion::Apollo::Local).to receive(:query).with(
            hash_including(question: 'What gotchas exist?')
          ).and_return(local_result)
          described_class.call(question: 'What gotchas exist?', scope: 'local')
        end
      end

      context 'when Legion::Apollo::Local is not available' do
        it 'falls back to global Runners::Query' do
          expect(Legion::Extensions::Knowledge::Runners::Query).to receive(:query).with(
            hash_including(question: 'What gotchas exist?')
          ).and_return(query_result)
          described_class.call(question: 'What gotchas exist?', scope: 'local')
        end
      end
    end

    context 'with scope: all (default)' do
      let(:global_result) { { answer: 'Global answer', sources: [{ chunk_id: 'g1', content: 'global chunk' }] } }
      let(:local_result)  { { answer: 'Local answer',  sources: [{ chunk_id: 'l1', content: 'local chunk' }] } }

      before do
        stub_const('Legion::Extensions::Knowledge::Runners::Query', Class.new)
        allow(Legion::Extensions::Knowledge::Runners::Query).to receive(:query).and_return(global_result)
      end

      it 'returns a successful response' do
        response = described_class.call(question: 'Tell me everything')
        expect(response.error?).to be false
      end

      context 'when Legion::Apollo::Local is available' do
        before do
          stub_const('Legion::Apollo::Local', Class.new)
          allow(Legion::Apollo::Local).to receive(:query).and_return(local_result)
        end

        it 'queries both global and local' do
          expect(Legion::Extensions::Knowledge::Runners::Query).to receive(:query).and_return(global_result)
          expect(Legion::Apollo::Local).to receive(:query).and_return(local_result)
          described_class.call(question: 'Tell me everything')
        end

        it 'merges sources from both results' do
          response = described_class.call(question: 'Tell me everything')
          data = Legion::JSON.load(response.content.first[:text])
          expect(data[:sources].length).to eq(2)
        end
      end
    end
  end
end
