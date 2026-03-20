# frozen_string_literal: true

require 'spec_helper'
require 'legion/mcp'

RSpec.describe Legion::MCP::Tools::DoAction do
  let(:mock_response) do
    MCP::Tool::Response.new([{ type: 'text', text: Legion::JSON.dump({ result: 'ok' }) }])
  end

  let(:mock_tool_class) do
    klass = Class.new do
      def self.call(**_args); end
    end
    allow(klass).to receive(:call).and_return(mock_response)
    klass
  end

  describe '.call' do
    context 'when no matching tool is found' do
      before do
        allow(Legion::MCP::ContextCompiler).to receive(:match_tool).and_return(nil)
      end

      it 'returns an error response' do
        response = described_class.call(intent: 'xyzzy florp quux')
        expect(response).to be_a(MCP::Tool::Response)
        expect(response.error?).to be true
      end

      it 'includes the intent in the error message' do
        response = described_class.call(intent: 'xyzzy florp quux')
        data = Legion::JSON.load(response.content.first[:text])
        expect(data[:error]).to include('xyzzy florp quux')
      end
    end

    context 'when a matching tool is found' do
      before do
        allow(Legion::MCP::ContextCompiler).to receive(:match_tool).and_return(mock_tool_class)
      end

      it 'delegates to the matched tool' do
        expect(mock_tool_class).to receive(:call).and_return(mock_response)
        described_class.call(intent: 'run a task')
      end

      it 'returns the matched tool response' do
        response = described_class.call(intent: 'run a task')
        expect(response).to be_a(MCP::Tool::Response)
        expect(response.error?).to be false
      end

      it 'returns a successful response when tool succeeds' do
        response = described_class.call(intent: 'run a task')
        expect(response.error?).to be false
      end
    end

    context 'when params are provided as string-keyed hash' do
      let(:string_keyed_params) { { 'task' => 'http.request.get', 'url' => 'https://example.com' } }

      before do
        allow(Legion::MCP::ContextCompiler).to receive(:match_tool).and_return(mock_tool_class)
      end

      it 'converts string keys to symbols before delegating' do
        expect(mock_tool_class).to receive(:call).with(task: 'http.request.get', url: 'https://example.com')
                                                 .and_return(mock_response)
        described_class.call(intent: 'run a task', params: string_keyed_params)
      end
    end

    context 'when params are symbol-keyed' do
      let(:symbol_keyed_params) { { task: 'http.request.get' } }

      before do
        allow(Legion::MCP::ContextCompiler).to receive(:match_tool).and_return(mock_tool_class)
      end

      it 'passes symbol-keyed params through to the tool' do
        expect(mock_tool_class).to receive(:call).with(task: 'http.request.get').and_return(mock_response)
        described_class.call(intent: 'run a task', params: symbol_keyed_params)
      end
    end

    context 'when params default to empty hash' do
      before do
        allow(Legion::MCP::ContextCompiler).to receive(:match_tool).and_return(mock_tool_class)
      end

      it 'calls tool with no keyword args when params is empty' do
        expect(mock_tool_class).to receive(:call).with(no_args).and_return(mock_response)
        described_class.call(intent: 'run a task')
      end
    end

    context 'when match_tool raises an error' do
      before do
        allow(Legion::MCP::ContextCompiler).to receive(:match_tool).and_raise(StandardError, 'compile error')
      end

      it 'returns an error response' do
        response = described_class.call(intent: 'run a task')
        expect(response.error?).to be true
        data = Legion::JSON.load(response.content.first[:text])
        expect(data[:error]).to include('compile error')
      end
    end

    describe 'observer feedback' do
      before do
        Legion::MCP::Observer.reset!
      end

      it 'records the actual matched tool name in observer, not legion.do' do
        stub_tool = Class.new(::MCP::Tool) do
          tool_name 'legion.list_tasks'
          description 'stub'
        end
        allow(Legion::MCP::ContextCompiler).to receive(:match_tool).and_return(stub_tool)
        allow(stub_tool).to receive(:call).and_return(
          MCP::Tool::Response.new([{ type: 'text', text: '{}' }])
        )

        described_class.call(intent: 'fetch api data')

        recent = Legion::MCP::Observer.recent_intents(1).last
        expect(recent[:matched_tool]).to eq('legion.list_tasks')
      end

      it 'records tool name even when tool does not respond to tool_name' do
        stub_tool = Class.new do
          def self.call(**_args)
            MCP::Tool::Response.new([{ type: 'text', text: '{}' }])
          end
        end
        allow(Legion::MCP::ContextCompiler).to receive(:match_tool).and_return(stub_tool)

        described_class.call(intent: 'run something')

        recent = Legion::MCP::Observer.recent_intents(1).last
        expect(recent[:matched_tool]).to be_a(String)
        expect(recent[:matched_tool]).not_to be_empty
      end
    end

    describe 'Tier 0 routing' do
      before do
        require 'legion/mcp/tier_router'
        Legion::MCP::PatternStore.reset!
        Legion::MCP::ContextGuard.reset!
      end

      context 'when tier 0 is enabled and pattern matches' do
        it 'returns tier 0 response without calling ContextCompiler' do
          allow(Legion::MCP::TierRouter).to receive(:route)
            .and_return({ tier: 0, response: { status: 'ok' }, latency_ms: 2.1, pattern_confidence: 0.92 })

          result = described_class.call(intent: 'check status')
          expect(result).to be_a(::MCP::Tool::Response)
        end
      end

      context 'when tier router returns tier 2 (no pattern)' do
        it 'falls back to ContextCompiler matching when LLM unavailable' do
          allow(Legion::MCP::TierRouter).to receive(:route)
            .and_return({ tier: 2, response: nil, reason: 'no pattern' })

          allow(Legion::MCP::ContextCompiler).to receive(:match_tool).and_return(nil)

          result = described_class.call(intent: 'unknown thing')
          expect(result).to be_a(::MCP::Tool::Response)
        end
      end
    end

    describe 'Tier 1 execution' do
      let(:llm_mod) do
        Module.new do
          def self.started?; true; end
          def self.ask(_prompt, **_opts); 'LLM result'; end
        end
      end

      before do
        require 'legion/mcp/tier_router'
        Legion::MCP::PatternStore.reset!
        Legion::MCP::ContextGuard.reset!
      end

      it 'uses LLM with pattern hint when tier 1 is returned' do
        stub_const('Legion::LLM', llm_mod)
        allow(Legion::MCP::TierRouter).to receive(:route).and_return(
          tier: 1, response: nil,
          pattern: { tool_chain: ['legion.get_status'], intent_text: 'check status' },
          reason: 'confidence below tier 0'
        )

        result = described_class.call(intent: 'check deploy status')
        expect(result).to be_a(::MCP::Tool::Response)
        data = Legion::JSON.load(result.content.first[:text])
        expect(data[:_meta][:tier]).to eq(1)
      end

      it 'falls through to ContextCompiler when LLM unavailable' do
        hide_const('Legion::LLM') if defined?(Legion::LLM)
        allow(Legion::MCP::TierRouter).to receive(:route).and_return(
          tier: 1, response: nil,
          pattern: { tool_chain: ['legion.get_status'], intent_text: 'check status' },
          reason: 'confidence below tier 0'
        )
        allow(Legion::MCP::ContextCompiler).to receive(:match_tool).and_return(nil)

        result = described_class.call(intent: 'check deploy status')
        expect(result).to be_a(::MCP::Tool::Response)
        expect(Legion::MCP::ContextCompiler).to have_received(:match_tool)
      end
    end

    describe 'Tier 2 execution' do
      let(:llm_mod) do
        Module.new do
          def self.started?; true; end
          def self.ask(_prompt, **_opts); 'Cloud LLM result'; end
        end
      end

      before do
        require 'legion/mcp/tier_router'
        Legion::MCP::PatternStore.reset!
        Legion::MCP::ContextGuard.reset!
      end

      it 'uses cloud LLM with catalog context when available' do
        stub_const('Legion::LLM', llm_mod)
        allow(Legion::MCP::TierRouter).to receive(:route).and_return(
          tier: 2, response: nil, reason: 'no pattern'
        )
        allow(Legion::MCP::ContextCompiler).to receive(:compressed_catalog).and_return(
          [{ category: 'http', tool_count: 3 }]
        )

        result = described_class.call(intent: 'do something novel')
        data = Legion::JSON.load(result.content.first[:text])
        expect(data[:_meta][:tier]).to eq(2)
      end

      it 'falls back to ContextCompiler keyword match when LLM unavailable' do
        hide_const('Legion::LLM') if defined?(Legion::LLM)
        allow(Legion::MCP::TierRouter).to receive(:route).and_return(
          tier: 2, response: nil, reason: 'no pattern'
        )
        stub_tool = Class.new do
          def self.call(**)
            MCP::Tool::Response.new([{ type: 'text', text: '{}' }])
          end
        end
        allow(Legion::MCP::ContextCompiler).to receive(:match_tool).and_return(stub_tool)

        result = described_class.call(intent: 'do something')
        expect(Legion::MCP::ContextCompiler).to have_received(:match_tool)
      end
    end
  end
end
