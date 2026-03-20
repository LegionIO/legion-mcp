# frozen_string_literal: true

require 'spec_helper'
require 'legion/mcp'
require 'legion/mcp/pattern_store'
require 'legion/mcp/pattern_compiler'

RSpec.describe Legion::MCP::PatternCompiler do
  describe '.compile_tool_definitions' do
    it 'generates compressed tool definitions from TOOL_CLASSES' do
      result = described_class.compile_tool_definitions
      expect(result).to be_an(Array)
      expect(result.size).to eq(Legion::MCP::Server::TOOL_CLASSES.size)
    end

    it 'includes name and compressed fields' do
      result = described_class.compile_tool_definitions
      first = result.first
      expect(first).to include(:name, :compressed, :full_description)
      expect(first[:compressed].length).to be <= 200
    end

    it 'extracts parameter names from input_schema' do
      result = described_class.compile_tool_definitions
      do_action = result.find { |t| t[:name] == 'legion.do' }
      expect(do_action[:compressed]).to include('intent')
    end
  end

  describe '.compile_workflows' do
    before { Legion::MCP::PatternStore.reset! }

    it 'generates workflows from promoted patterns above threshold' do
      Legion::MCP::PatternStore.store(
        intent_hash: 'wf_test', intent_text: 'check health',
        tool_chain: ['legion.get_status'], confidence: 0.85,
        hit_count: 10, miss_count: 0, created_at: Time.now
      )

      workflows = described_class.compile_workflows
      expect(workflows).to be_an(Array)
      expect(workflows.size).to eq(1)
      expect(workflows.first).to include(:intent, :tools, :confidence)
      expect(workflows.first[:intent]).to eq('check health')
    end

    it 'excludes low-confidence patterns' do
      Legion::MCP::PatternStore.store(
        intent_hash: 'low_conf', intent_text: 'test',
        tool_chain: ['test'], confidence: 0.3,
        hit_count: 1, miss_count: 5, created_at: Time.now
      )

      expect(described_class.compile_workflows).to be_empty
    end
  end

  describe '.extract_params' do
    it 'extracts params from a tool class with input_schema' do
      params = described_class.extract_params(Legion::MCP::Tools::DoAction)
      expect(params).to include('intent')
    end

    it 'returns empty array for class without input_schema' do
      klass = Class.new
      expect(described_class.extract_params(klass)).to eq([])
    end
  end
end
