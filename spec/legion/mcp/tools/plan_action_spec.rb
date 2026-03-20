# frozen_string_literal: true

require 'spec_helper'
require 'legion/mcp'
require 'legion/mcp/tools/plan_action'

RSpec.describe Legion::MCP::Tools::PlanAction do
  describe '.call' do
    it 'returns a multi-step plan for a complex goal' do
      allow(Legion::MCP::ContextCompiler).to receive(:match_tools).and_return([
                                                                                { name: 'legion.get_status', score: 0.9, description: 'Get status' },
                                                                                { name: 'legion.list_tasks', score: 0.7, description: 'List tasks' }
                                                                              ])

      result = described_class.call(goal: 'check service health and list running tasks')
      body = Legion::JSON.load(result.content.first[:text])
      expect(body[:steps]).to be_an(Array)
      expect(body[:steps].size).to eq(2)
      expect(body[:steps].first[:tool]).to eq('legion.get_status')
      expect(body[:tool_count]).to eq(2)
    end

    it 'returns nil plan when no tools match' do
      allow(Legion::MCP::ContextCompiler).to receive(:match_tools).and_return([])

      result = described_class.call(goal: 'do something impossible')
      body = Legion::JSON.load(result.content.first[:text])
      expect(body[:plan]).to be_nil
      expect(body[:reason]).to include('no matching tools')
    end

    it 'includes narrative when LLM is available' do
      llm_mod = Module.new do
        def self.started?; true; end
        def self.ask(_prompt, **_opts); 'Step 1: Check status. Step 2: List tasks.'; end
      end
      stub_const('Legion::LLM', llm_mod)
      allow(Legion::MCP::ContextCompiler).to receive(:match_tools).and_return([
                                                                                { name: 'legion.get_status', score: 0.9, description: 'Get status' }
                                                                              ])

      result = described_class.call(goal: 'check health')
      body = Legion::JSON.load(result.content.first[:text])
      expect(body[:narrative]).to include('Step 1')
    end

    it 'returns plan without narrative when LLM is unavailable' do
      hide_const('Legion::LLM') if defined?(Legion::LLM)
      allow(Legion::MCP::ContextCompiler).to receive(:match_tools).and_return([
                                                                                { name: 'legion.get_status', score: 0.9, description: 'Get status' }
                                                                              ])

      result = described_class.call(goal: 'check health')
      body = Legion::JSON.load(result.content.first[:text])
      expect(body[:steps]).to be_an(Array)
      expect(body).not_to have_key(:narrative)
    end

    it 'returns error when ContextCompiler raises' do
      allow(Legion::MCP::ContextCompiler).to receive(:match_tools).and_raise(StandardError, 'compiler down')

      result = described_class.call(goal: 'check health')
      expect(result.error?).to be true
      body = Legion::JSON.load(result.content.first[:text])
      expect(body[:error]).to include('compiler down')
    end
  end
end
