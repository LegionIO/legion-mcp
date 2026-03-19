# frozen_string_literal: true

require 'spec_helper'
require 'legion/mcp/context_guard'

RSpec.describe Legion::MCP::ContextGuard do
  before { described_class.reset! }

  describe '.check' do
    let(:fresh_pattern) do
      { intent_hash: 'h1', confidence: 0.9, last_hit_at: Time.now - 60, miss_count: 0 }
    end

    it 'passes for a fresh, healthy pattern' do
      result = described_class.check(fresh_pattern, {}, {})
      expect(result[:passed]).to be true
    end

    context 'staleness guard' do
      it 'fails when pattern is stale' do
        stale = fresh_pattern.merge(last_hit_at: Time.now - 7200)
        result = described_class.check(stale, {}, {})
        expect(result[:passed]).to be false
        expect(result[:guard]).to eq(:staleness)
      end

      it 'passes when pattern has no last_hit_at (first use)' do
        no_hit = fresh_pattern.merge(last_hit_at: nil)
        result = described_class.check(no_hit, {}, {})
        expect(result[:passed]).to be true
      end
    end

    context 'anomaly guard' do
      it 'fails when miss_count >= 2' do
        anomaly = fresh_pattern.merge(miss_count: 2)
        result = described_class.check(anomaly, {}, {})
        expect(result[:passed]).to be false
        expect(result[:guard]).to eq(:anomaly)
      end
    end

    context 'rapid_fire guard' do
      it 'fails when same intent exceeds threshold in window' do
        6.times { described_class.record_request('h1') }
        result = described_class.check(fresh_pattern, {}, {})
        expect(result[:passed]).to be false
        expect(result[:guard]).to eq(:rapid_fire)
      end
    end
  end

  describe '.reset!' do
    it 'clears rapid fire tracking' do
      5.times { described_class.record_request('h1') }
      described_class.reset!
      result = described_class.check({ intent_hash: 'h1', confidence: 0.9,
                                       last_hit_at: Time.now, miss_count: 0 }, {}, {})
      expect(result[:passed]).to be true
    end
  end
end
