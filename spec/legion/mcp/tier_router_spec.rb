# frozen_string_literal: true

require 'spec_helper'
require 'digest'
require 'legion/mcp/pattern_store'
require 'legion/mcp/context_guard'
require 'legion/mcp/tier_router'

RSpec.describe Legion::MCP::TierRouter do
  let(:logger) { spy('logger') }

  before do
    Legion::MCP::PatternStore.reset!
    Legion::MCP::ContextGuard.reset!
    allow(Legion::MCP::TierRouter).to receive(:log).and_return(logger)
    allow(Legion::MCP::PatternStore).to receive(:log).and_return(logger)
  end

  describe '.route' do
    context 'with no patterns' do
      it 'returns tier 2' do
        result = described_class.route(intent: 'unknown action')
        expect(result[:tier]).to eq(2)
        expect(result[:response]).to be_nil
      end
    end

    context 'with low confidence pattern' do
      before do
        Legion::MCP::PatternStore.store(
          intent_hash: Digest::SHA256.hexdigest('check status'),
          intent_text: 'check status', tool_chain: ['legion.get_status'],
          confidence: 0.4, hit_count: 0, miss_count: 0, created_at: Time.now
        )
      end

      it 'returns tier 2' do
        result = described_class.route(intent: 'check status')
        expect(result[:tier]).to eq(2)
      end
    end

    context 'with medium confidence pattern (0.6-0.8)' do
      before do
        Legion::MCP::PatternStore.store(
          intent_hash: Digest::SHA256.hexdigest('check status'),
          intent_text: 'check status', tool_chain: ['legion.get_status'],
          confidence: 0.7, hit_count: 5, miss_count: 0, created_at: Time.now
        )
      end

      it 'returns tier 1 with pattern hint' do
        result = described_class.route(intent: 'check status')
        expect(result[:tier]).to eq(1)
        expect(result[:pattern]).not_to be_nil
      end
    end

    context 'with high confidence pattern (>= 0.8)' do
      before do
        Legion::MCP::PatternStore.store(
          intent_hash: Digest::SHA256.hexdigest('check status'),
          intent_text: 'check status', tool_chain: ['legion.get_status'],
          confidence: 0.9, hit_count: 10, miss_count: 0, created_at: Time.now,
          last_hit_at: Time.now - 30
        )
      end

      it 'returns tier 0 with response' do
        allow(described_class).to receive(:execute_tool_chain)
          .and_return([{ status: 'running' }])

        result = described_class.route(intent: 'check status')
        expect(result[:tier]).to eq(0)
        expect(result[:response]).not_to be_nil
        expect(result[:latency_ms]).to be_a(Numeric)
      end

      it 'logs the tier 0 routing lifecycle' do
        allow(described_class).to receive(:execute_tool_chain)
          .and_return([{ status: 'running' }])

        described_class.route(intent: 'check status', context: { request_id: 'req-tier0' })

        expect(logger).to have_received(:info).with(include('[mcp] tier_router.start', 'request_id="req-tier0"'))
        expect(logger).to have_received(:info).with(include('[mcp] tier_router.lookup', 'source=:exact'))
        expect(logger).to have_received(:info).with(include('[mcp] tier_router.complete', 'tier=0'))
      end
    end

    context 'when context guard fails' do
      before do
        Legion::MCP::PatternStore.store(
          intent_hash: Digest::SHA256.hexdigest('check status'),
          intent_text: 'check status', tool_chain: ['legion.get_status'],
          confidence: 0.9, hit_count: 10, miss_count: 2,
          created_at: Time.now, last_hit_at: Time.now
        )
      end

      it 'escalates to tier 1 with reason' do
        result = described_class.route(intent: 'check status')
        expect(result[:tier]).to eq(1)
        expect(result[:reason]).to include('misses')
      end
    end

    context 'when tool chain execution fails' do
      before do
        Legion::MCP::PatternStore.store(
          intent_hash: Digest::SHA256.hexdigest('check status'),
          intent_text: 'check status', tool_chain: ['legion.get_status'],
          confidence: 0.9, hit_count: 10, miss_count: 0,
          created_at: Time.now, last_hit_at: Time.now - 30
        )
        allow(described_class).to receive(:execute_tool_chain)
          .and_raise(StandardError, 'tool failed')
      end

      it 'escalates to tier 1 and records miss' do
        result = described_class.route(intent: 'check status')
        expect(result[:tier]).to eq(1)
        pattern = Legion::MCP::PatternStore.lookup(Digest::SHA256.hexdigest('check status'))
        expect(pattern[:miss_count]).to eq(1)
      end
    end
  end

  describe '.normalize_intent' do
    it 'downcases and strips whitespace' do
      expect(described_class.normalize_intent('  Check STATUS  ')).to eq('check status')
    end

    it 'collapses multiple spaces' do
      expect(described_class.normalize_intent('check  the   status')).to eq('check the status')
    end
  end
end
