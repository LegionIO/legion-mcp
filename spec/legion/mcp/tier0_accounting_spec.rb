# frozen_string_literal: true

require 'spec_helper'
require 'digest'
require 'legion/mcp/pattern_store'
require 'legion/mcp/context_guard'
require 'legion/mcp/tier_router'
require 'legion/mcp/observer'

RSpec.describe 'Tier 0 pattern learning and promotion accounting' do
  let(:logger) { spy('logger') }

  before do
    Legion::MCP::PatternStore.reset!
    Legion::MCP::ContextGuard.reset!
    Legion::MCP::Observer.reset!
    allow(Legion::MCP::LoggingSupport).to receive(:log).and_return(logger)
  end

  # ---------------------------------------------------------------------------
  # Fix 1: tier_router.rb records against matched pattern hash, not incoming
  # ---------------------------------------------------------------------------
  describe 'TierRouter tracks matched pattern hash after semantic lookup' do
    let(:stored_hash) { 'stored_pattern_hash_abc' }
    let(:incoming_hash) { Digest::SHA256.hexdigest('similar but different intent') }

    before do
      Legion::MCP::PatternStore.store(
        intent_hash:   stored_hash,
        intent_text:   'check deploy status',
        intent_vector: [0.1, 0.9, 0.3, 0.5],
        tool_chain:    ['legion.get_status'],
        confidence:    0.9,
        hit_count:     5,
        miss_count:    0,
        created_at:    Time.now,
        last_hit_at:   Time.now - 30
      )
    end

    it 'records hit against the matched pattern hash on success' do
      # Simulate semantic lookup returning the stored pattern for a different intent
      allow(Legion::MCP::TierRouter).to receive(:try_semantic_lookup).and_return(
        Legion::MCP::PatternStore.lookup(stored_hash)
      )
      allow(Legion::MCP::TierRouter).to receive(:execute_tool_chain)
        .and_return([{ status: 'running' }])

      Legion::MCP::TierRouter.route(intent: 'similar but different intent')

      stored = Legion::MCP::PatternStore.lookup(stored_hash)
      expect(stored[:hit_count]).to eq(6)
    end

    it 'records miss against the matched pattern hash on tool chain failure' do
      allow(Legion::MCP::TierRouter).to receive(:try_semantic_lookup).and_return(
        Legion::MCP::PatternStore.lookup(stored_hash)
      )
      allow(Legion::MCP::TierRouter).to receive(:execute_tool_chain)
        .and_raise(StandardError, 'tool failed')

      Legion::MCP::TierRouter.route(intent: 'similar but different intent')

      stored = Legion::MCP::PatternStore.lookup(stored_hash)
      expect(stored[:miss_count]).to eq(1)
      expect(stored[:confidence]).to be < 0.9
    end

    it 'does not record against the incoming intent hash' do
      allow(Legion::MCP::TierRouter).to receive(:try_semantic_lookup).and_return(
        Legion::MCP::PatternStore.lookup(stored_hash)
      )
      allow(Legion::MCP::TierRouter).to receive(:execute_tool_chain)
        .and_return([{ status: 'running' }])

      Legion::MCP::TierRouter.route(intent: 'similar but different intent')

      # The incoming intent hash should not have a pattern stored
      expect(Legion::MCP::PatternStore.lookup(incoming_hash)).to be_nil
    end
  end

  # ---------------------------------------------------------------------------
  # Fix 2: promotion identity includes tool name (candidate_key)
  # ---------------------------------------------------------------------------
  describe 'promotion identity includes tool name' do
    it 'tracks separate counters for same intent but different tools' do
      # Record 2 observations for tool_a
      2.times do
        Legion::MCP::Observer.record_intent_with_result(
          intent:    'check status',
          tool_name: 'legion.tool_a',
          success:   true
        )
      end

      # Record 2 observations for tool_b (same intent)
      2.times do
        Legion::MCP::Observer.record_intent_with_result(
          intent:    'check status',
          tool_name: 'legion.tool_b',
          success:   true
        )
      end

      # Neither should be promoted yet (threshold is 3)
      hash = Digest::SHA256.hexdigest('check status')
      expect(Legion::MCP::PatternStore.lookup(hash)).to be_nil
    end

    it 'promotes only the tool that reaches threshold independently' do
      # Record 3 observations for tool_a
      3.times do
        Legion::MCP::Observer.record_intent_with_result(
          intent:    'check status',
          tool_name: 'legion.tool_a',
          success:   true
        )
      end

      hash = Digest::SHA256.hexdigest('check status')
      pattern = Legion::MCP::PatternStore.lookup(hash)
      expect(pattern).not_to be_nil
      expect(pattern[:tool_chain]).to eq(['legion.tool_a'])
    end

    it 'does not promote when observations are split across tools below threshold' do
      # 2 for tool_a + 2 for tool_b = 4 total, but neither reaches 3 alone
      2.times do
        Legion::MCP::Observer.record_intent_with_result(
          intent:    'run diagnostics',
          tool_name: 'legion.diagnostics_v1',
          success:   true
        )
      end
      2.times do
        Legion::MCP::Observer.record_intent_with_result(
          intent:    'run diagnostics',
          tool_name: 'legion.diagnostics_v2',
          success:   true
        )
      end

      hash = Digest::SHA256.hexdigest('run diagnostics')
      expect(Legion::MCP::PatternStore.lookup(hash)).to be_nil
    end
  end

  # ---------------------------------------------------------------------------
  # Fix 3: do_action error response handling
  # ---------------------------------------------------------------------------
  describe 'DoAction error response feedback' do
    let(:mock_tool_class) do
      Class.new do
        def self.tool_name = 'legion.failing_tool'

        def self.call(**_args)
          MCP::Tool::Response.new([{ type: 'text', text: '{"error":"something broke"}' }], error: true)
        end
      end
    end

    let(:success_tool_class) do
      Class.new do
        def self.tool_name = 'legion.success_tool'

        def self.call(**_args)
          MCP::Tool::Response.new([{ type: 'text', text: '{"status":"ok"}' }])
        end
      end
    end

    before do
      stub_const('Legion::MCP::ContextCompiler', Module.new)
    end

    it 'records error responses as failures' do
      allow(Legion::MCP::ContextCompiler).to receive(:match_tool).and_return(mock_tool_class)

      expect(Legion::MCP::Observer).to receive(:record_intent_with_result).with(
        hash_including(intent: 'do something', tool_name: 'legion.failing_tool', success: false)
      )

      # Need to stub TierRouter to be unavailable so we fall through to ContextCompiler
      Legion::MCP::Tools::DoAction.call(intent: 'do something')
    end

    it 'records non-error responses as successes' do
      allow(Legion::MCP::ContextCompiler).to receive(:match_tool).and_return(success_tool_class)

      expect(Legion::MCP::Observer).to receive(:record_intent_with_result).with(
        hash_including(intent: 'do something', tool_name: 'legion.success_tool', success: true)
      )

      Legion::MCP::Tools::DoAction.call(intent: 'do something')
    end
  end
end
