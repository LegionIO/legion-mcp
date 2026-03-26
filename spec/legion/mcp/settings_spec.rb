# frozen_string_literal: true

require 'spec_helper'
require 'legion/mcp/settings'

RSpec.describe Legion::MCP::Settings do
  describe '.defaults' do
    subject(:defaults) { described_class.defaults }

    it 'includes codegen self_generate settings' do
      expect(defaults[:codegen][:self_generate][:enabled]).to eq(false)
      expect(defaults[:codegen][:self_generate][:cooldown_seconds]).to eq(300)
      expect(defaults[:codegen][:self_generate][:max_gaps_per_cycle]).to eq(5)
    end

    it 'includes tier thresholds' do
      tier = defaults[:codegen][:self_generate][:tier]
      expect(tier[:simple_max_occurrences]).to eq(10)
      expect(tier[:complex_min_occurrences]).to eq(11)
    end

    it 'includes validation settings' do
      validation = defaults[:codegen][:self_generate][:validation]
      expect(validation[:syntax_check]).to eq(true)
      expect(validation[:run_specs]).to eq(true)
      expect(validation[:llm_review]).to eq(true)
      expect(validation[:max_retries]).to eq(2)
      expect(validation[:quality_gate][:enabled]).to eq(false)
    end

    it 'includes approval settings defaulting to autonomous' do
      approval = defaults[:codegen][:self_generate][:approval]
      expect(approval[:required]).to eq(false)
      expect(approval[:auto_approve_confidence]).to eq(0.9)
    end

    it 'includes hot_register settings' do
      hr = defaults[:codegen][:self_generate][:hot_register]
      expect(hr[:mcp_tools]).to eq(true)
      expect(hr[:full_load_on_boot]).to eq(true)
    end

    it 'includes corroboration settings' do
      corr = defaults[:codegen][:self_generate][:corroboration]
      expect(corr[:enabled]).to eq(true)
      expect(corr[:min_agents]).to eq(2)
    end

    it 'includes github lifecycle settings disabled by default' do
      gh = defaults[:codegen][:self_generate][:github]
      expect(gh[:enabled]).to eq(false)
      expect(gh[:auto_merge]).to eq(false)
    end

    it 'includes mcp auto_expose_runners defaulting to false' do
      expect(defaults[:mcp][:auto_expose_runners]).to eq(false)
    end
  end
end
