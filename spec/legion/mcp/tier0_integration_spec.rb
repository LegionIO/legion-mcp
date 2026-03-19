# frozen_string_literal: true

require 'spec_helper'
require 'legion/mcp/pattern_store'
require 'legion/mcp/context_guard'
require 'legion/mcp/tier_router'
require 'legion/mcp/observer'

RSpec.describe 'Tier 0 Integration' do
  before do
    Legion::MCP::PatternStore.reset!
    Legion::MCP::ContextGuard.reset!
    Legion::MCP::Observer.reset!
  end

  describe 'full lifecycle: observe -> promote -> serve' do
    let(:mock_tool_class) do
      Class.new do
        def self.tool_name = 'legion.get_status'
        def self.call(**_args) = ::MCP::Tool::Response.new([{ type: 'text', text: '{"status":"ok"}' }])
      end
    end

    before do
      stub_const('Legion::MCP::Server::TOOL_CLASSES', [mock_tool_class])
    end

    it 'promotes after 3 observations and serves tier 0' do
      # Phase 1: Record 3 successful observations
      3.times do
        Legion::MCP::Observer.record_intent_with_result(
          intent:    'check system status',
          tool_name: 'legion.get_status',
          success:   true
        )
      end

      # Pattern should now exist
      hash = Digest::SHA256.hexdigest('check system status')
      pattern = Legion::MCP::PatternStore.lookup(hash)
      expect(pattern).not_to be_nil
      expect(pattern[:confidence]).to eq(0.5)

      # Phase 2: Simulate confidence growth (manual for testing)
      pattern[:confidence] = 0.9
      pattern[:last_hit_at] = Time.now
      Legion::MCP::PatternStore.store(pattern)

      # Phase 3: Route should return Tier 0
      result = Legion::MCP::TierRouter.route(intent: 'check system status')
      expect(result[:tier]).to eq(0)
      expect(result[:response]).not_to be_nil
    end
  end

  describe 'degradation: no cache, no local' do
    it 'works with L0 only (in-memory)' do
      Legion::MCP::PatternStore.store(
        intent_hash: Digest::SHA256.hexdigest('test intent'),
        intent_text: 'test intent',
        tool_chain:  ['legion.get_status'],
        confidence:  0.9, hit_count: 5, miss_count: 0,
        created_at:  Time.now, last_hit_at: Time.now - 30
      )

      mock_tool = Class.new do
        def self.tool_name = 'legion.get_status'
        def self.call(**_args) = ::MCP::Tool::Response.new([{ type: 'text', text: '{"ok":true}' }])
      end
      stub_const('Legion::MCP::Server::TOOL_CLASSES', [mock_tool])

      result = Legion::MCP::TierRouter.route(intent: 'test intent')
      expect(result[:tier]).to eq(0)
    end
  end

  describe 'escalation on failure' do
    it 'demotes pattern after tool chain failure' do
      hash = Digest::SHA256.hexdigest('failing intent')
      Legion::MCP::PatternStore.store(
        intent_hash: hash, intent_text: 'failing intent',
        tool_chain:  ['legion.nonexistent_tool'],
        confidence:  0.85, hit_count: 10, miss_count: 0,
        created_at:  Time.now, last_hit_at: Time.now - 30
      )

      stub_const('Legion::MCP::Server::TOOL_CLASSES', [])

      result = Legion::MCP::TierRouter.route(intent: 'failing intent')
      expect(result[:tier]).to eq(1)

      pattern = Legion::MCP::PatternStore.lookup(hash)
      expect(pattern[:miss_count]).to eq(1)
      expect(pattern[:confidence]).to be < 0.85
    end
  end

  describe 'semantic matching' do
    it 'matches similar intents via cosine similarity' do
      vec = [0.1, 0.9, 0.3, 0.5]
      Legion::MCP::PatternStore.store(
        intent_hash: 'exact_hash', intent_text: 'check deploy status',
        intent_vector: vec, tool_chain: ['legion.get_status'],
        confidence: 0.9, hit_count: 5, miss_count: 0,
        created_at: Time.now, last_hit_at: Time.now - 30
      )

      similar_vec = [0.11, 0.89, 0.31, 0.49]
      result = Legion::MCP::PatternStore.lookup_semantic(similar_vec, threshold: 0.99)
      expect(result).not_to be_nil
      expect(result[:intent_text]).to eq('check deploy status')
    end
  end
end
