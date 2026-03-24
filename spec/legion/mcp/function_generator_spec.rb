# frozen_string_literal: true

require 'spec_helper'
require 'legion/mcp/pattern_store'
require 'legion/mcp/function_generator'

RSpec.describe Legion::MCP::FunctionGenerator do
  before { Legion::MCP::PatternStore.reset! }

  let(:llm_stub) do
    Module.new do
      def self.chat(message:, caller: nil) # rubocop:disable Lint/UnusedMethodArgument
        resp = Object.new
        resp.define_singleton_method(:content) do
          '{"name":"legion.test_tool","description":"Does stuff",' \
            '"runner_function":"my_ext/runner/action","parameters":[],"category":"utility"}'
        end
        resp
      end
    end
  end

  let(:unmatched_gap) do
    { id: 'unmatched:abc123', type: :unmatched_intent, intent: 'fetch deployment status',
      occurrences: 7, priority: 0.94 }
  end

  let(:failure_gap) do
    { id: 'failing:bad.tool', type: :high_failure_tool, tool_name: 'bad.tool',
      failure_rate: 0.6, call_count: 10, failure_count: 6, last_error: 'connection refused', priority: 0.72 }
  end

  let(:stale_gap) do
    { id: 'stale:deadbeef1234', type: :stale_candidate, intent_text: 'restart the node',
      tool_chain: ['infra.restart'], observation_count: 3, priority: 0.46 }
  end

  # ---------------------------------------------------------------------------
  # generate_from_gap — dispatch
  # ---------------------------------------------------------------------------
  describe '.generate_from_gap' do
    it 'dispatches unmatched_intent to generate_tool_for_intent' do
      allow(described_class).to receive(:generate_tool_for_intent).and_return({ success: true })
      result = described_class.generate_from_gap(unmatched_gap)
      expect(result[:success]).to be true
      expect(described_class).to have_received(:generate_tool_for_intent).with(intent: 'fetch deployment status')
    end

    it 'dispatches high_failure_tool to generate_fix_for_tool' do
      allow(described_class).to receive(:generate_fix_for_tool).and_return({ success: true })
      result = described_class.generate_from_gap(failure_gap)
      expect(result[:success]).to be true
      expect(described_class).to have_received(:generate_fix_for_tool)
        .with(tool_name: 'bad.tool', last_error: 'connection refused')
    end

    it 'dispatches stale_candidate to generate_tool_for_candidate' do
      allow(described_class).to receive(:generate_tool_for_candidate).and_return({ success: true })
      result = described_class.generate_from_gap(stale_gap)
      expect(result[:success]).to be true
    end

    it 'returns unknown_gap_type for unrecognised type' do
      result = described_class.generate_from_gap({ id: 'x', type: :mystery_type })
      expect(result[:success]).to be false
      expect(result[:reason]).to eq(:unknown_gap_type)
    end

    it 'rescues exceptions and returns failure hash' do
      allow(described_class).to receive(:generate_tool_for_intent).and_raise(RuntimeError, 'exploded')
      result = described_class.generate_from_gap(unmatched_gap)
      expect(result[:success]).to be false
      expect(result[:reason]).to eq(:generation_failed)
      expect(result[:error]).to eq('exploded')
    end
  end

  # ---------------------------------------------------------------------------
  # generate_tool_for_intent
  # ---------------------------------------------------------------------------
  describe '.generate_tool_for_intent' do
    it 'returns llm_not_available when LLM not defined' do
      result = described_class.generate_tool_for_intent(intent: 'do something')
      expect(result[:success]).to be false
      expect(result[:reason]).to eq(:llm_not_available)
    end

    it 'calls LLM with the intent and returns validated spec' do
      stub_const('Legion::LLM', llm_stub)
      result = described_class.generate_tool_for_intent(intent: 'fetch deployment status')
      expect(result[:success]).to be true
      expect(result[:tool_spec]).to be_a(Hash)
      expect(result[:tool_spec][:name]).to eq('legion.test_tool')
    end

    it 'returns llm_failed when LLM returns nil content' do
      stub_const('Legion::LLM', llm_stub)
      allow(described_class).to receive(:llm_ask).and_return(nil)
      result = described_class.generate_tool_for_intent(intent: 'query x')
      expect(result[:success]).to be false
      expect(result[:reason]).to eq(:llm_failed)
    end

    it 'returns parse_failed when response is not valid JSON' do
      stub_const('Legion::LLM', llm_stub)
      allow(described_class).to receive(:llm_ask).and_return('not json at all')
      result = described_class.generate_tool_for_intent(intent: 'something')
      expect(result[:success]).to be false
      expect(result[:reason]).to eq(:parse_failed)
    end
  end

  # ---------------------------------------------------------------------------
  # generate_fix_for_tool
  # ---------------------------------------------------------------------------
  describe '.generate_fix_for_tool' do
    it 'returns llm_not_available when LLM not defined' do
      result = described_class.generate_fix_for_tool(tool_name: 'bad.tool', last_error: 'timeout')
      expect(result[:success]).to be false
      expect(result[:reason]).to eq(:llm_not_available)
    end

    it 'returns a fix suggestion when LLM available' do
      fix_llm = Module.new do
        def self.chat(message:, caller: nil) # rubocop:disable Lint/UnusedMethodArgument
          resp = Object.new
          resp.define_singleton_method(:content) { 'Increase the connection timeout in config.' }
          resp
        end
      end
      stub_const('Legion::LLM', fix_llm)
      result = described_class.generate_fix_for_tool(tool_name: 'bad.tool', last_error: 'timeout')
      expect(result[:success]).to be true
      expect(result[:type]).to eq(:fix_suggestion)
      expect(result[:tool_name]).to eq('bad.tool')
      expect(result[:suggestion]).to eq('Increase the connection timeout in config.')
      expect(result[:requires_review]).to be true
    end

    it 'returns llm_failed when LLM returns nil' do
      stub_const('Legion::LLM', llm_stub)
      allow(described_class).to receive(:llm_ask).and_return(nil)
      result = described_class.generate_fix_for_tool(tool_name: 'bad.tool', last_error: 'err')
      expect(result[:reason]).to eq(:llm_failed)
    end
  end

  # ---------------------------------------------------------------------------
  # generate_tool_for_candidate
  # ---------------------------------------------------------------------------
  describe '.generate_tool_for_candidate' do
    it 'returns llm_not_available when LLM not defined' do
      result = described_class.generate_tool_for_candidate(intent_text: 'restart node', tool_chain: ['infra.restart'])
      expect(result[:success]).to be false
      expect(result[:reason]).to eq(:llm_not_available)
    end

    it 'generates and registers a pattern when LLM available' do
      stub_const('Legion::LLM', llm_stub)
      result = described_class.generate_tool_for_candidate(
        intent_text: 'restart the node', tool_chain: ['infra.restart']
      )
      expect(result[:success]).to be true
      # Pattern should be registered in PatternStore
      hash = Digest::SHA256.hexdigest('restart the node')
      expect(Legion::MCP::PatternStore.lookup(hash)).not_to be_nil
    end

    it 'passes existing_chain context to the prompt' do
      stub_const('Legion::LLM', llm_stub)
      allow(described_class).to receive(:generate_tool_spec).and_call_original
      described_class.generate_tool_for_candidate(intent_text: 'do x', tool_chain: ['a.runner'])
      expect(described_class).to have_received(:generate_tool_spec)
        .with(intent: 'do x', existing_chain: ['a.runner'])
    end
  end

  # ---------------------------------------------------------------------------
  # validate_spec
  # ---------------------------------------------------------------------------
  describe '.validate_spec' do
    let(:valid_spec) do
      { name: 'legion.good', description: 'Does something', runner_function: 'ext/runner/method',
        parameters: [], category: 'utility' }
    end

    it 'returns success and valid: true for a complete spec' do
      result = described_class.validate_spec(valid_spec)
      expect(result[:success]).to be true
      expect(result[:valid]).to be true
    end

    it 'catches missing name' do
      spec = valid_spec.merge(name: '')
      result = described_class.validate_spec(spec)
      expect(result[:success]).to be false
      expect(result[:errors]).to include('missing name')
    end

    it 'catches missing description' do
      spec = valid_spec.merge(description: nil)
      result = described_class.validate_spec(spec)
      expect(result[:success]).to be false
      expect(result[:errors]).to include('missing description')
    end

    it 'catches missing runner_function' do
      spec = valid_spec.merge(runner_function: '')
      result = described_class.validate_spec(spec)
      expect(result[:success]).to be false
      expect(result[:errors]).to include('missing runner_function')
    end

    it 'accumulates multiple errors' do
      result = described_class.validate_spec({ name: '', description: '', runner_function: '' })
      expect(result[:errors].size).to eq(3)
    end
  end

  # ---------------------------------------------------------------------------
  # parse_tool_spec
  # ---------------------------------------------------------------------------
  describe '.parse_tool_spec' do
    it 'parses a plain JSON object' do
      raw = '{"name":"legion.foo","description":"bar","runner_function":"ext/r/m"}'
      result = described_class.parse_tool_spec(raw)
      expect(result).to be_a(Hash)
      expect(result[:name]).to eq('legion.foo')
    end

    it 'extracts JSON from markdown-wrapped response' do
      raw = "Sure! Here's the spec:\n```json\n{\"name\":\"legion.bar\",\"description\":\"baz\",\"runner_function\":\"ext/r/m\"}\n```"
      result = described_class.parse_tool_spec(raw)
      expect(result[:name]).to eq('legion.bar')
    end

    it 'returns nil for non-JSON text' do
      expect(described_class.parse_tool_spec('no json here')).to be_nil
    end

    it 'returns nil when parsed object has no :name key' do
      expect(described_class.parse_tool_spec('{"foo":"bar"}')).to be_nil
    end

    it 'returns nil for malformed JSON' do
      expect(described_class.parse_tool_spec('{name: bad json}')).to be_nil
    end
  end

  # ---------------------------------------------------------------------------
  # register_generated_pattern
  # ---------------------------------------------------------------------------
  describe '.register_generated_pattern' do
    it 'stores a pattern in PatternStore keyed by normalized intent hash' do
      spec = { name: 'legion.auto', description: 'generated', runner_function: 'ext/r/m' }
      described_class.register_generated_pattern(spec, 'Deploy To Staging')
      hash = Digest::SHA256.hexdigest('deploy to staging')
      expect(Legion::MCP::PatternStore.lookup(hash)).not_to be_nil
    end

    it 'uses runner_function as tool_chain entry' do
      spec = { name: 'legion.auto', description: 'gen', runner_function: 'my_ext/runner/go' }
      described_class.register_generated_pattern(spec, 'go do it')
      hash = Digest::SHA256.hexdigest('go do it')
      pattern = Legion::MCP::PatternStore.lookup(hash)
      expect(pattern[:tool_chain]).to include('my_ext/runner/go')
    end

    it 'falls back to name when runner_function is absent' do
      spec = { name: 'legion.fallback', description: 'gen' }
      described_class.register_generated_pattern(spec, 'fallback intent')
      hash = Digest::SHA256.hexdigest('fallback intent')
      pattern = Legion::MCP::PatternStore.lookup(hash)
      expect(pattern[:tool_chain]).to include('legion.fallback')
    end

    it 'does nothing when PatternStore not defined' do
      hide_const('Legion::MCP::PatternStore')
      spec = { name: 'legion.ghost', description: 'gen', runner_function: 'x/r/m' }
      expect { described_class.register_generated_pattern(spec, 'ghost intent') }.not_to raise_error
    end
  end

  # ---------------------------------------------------------------------------
  # llm_available?
  # ---------------------------------------------------------------------------
  describe '.llm_available?' do
    it 'returns falsey when Legion::LLM not defined' do
      expect(described_class.llm_available?).to be_falsey
    end

    it 'returns false when Legion::LLM does not respond to :chat' do
      stub_const('Legion::LLM', Module.new)
      expect(described_class.llm_available?).to be false
    end

    it 'returns true when Legion::LLM responds to :chat' do
      stub_const('Legion::LLM', llm_stub)
      expect(described_class.llm_available?).to be true
    end
  end
end
