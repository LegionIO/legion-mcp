# frozen_string_literal: true

require 'spec_helper'
require 'legion/mcp/observer'
require 'legion/mcp/pattern_store'
require 'legion/mcp/gap_detector'

RSpec.describe Legion::MCP::GapDetector do
  before do
    Legion::MCP::Observer.reset!
    Legion::MCP::PatternStore.reset!
  end

  describe '.analyze' do
    it 'returns an array' do
      expect(described_class.analyze).to be_an(Array)
    end

    it 'identifies repeated tool chain patterns' do
      5.times do
        Legion::MCP::Observer.record(tool_name: 'http.request.get', duration_ms: 100, success: true)
        Legion::MCP::Observer.record(tool_name: 'consul.kv.put', duration_ms: 50, success: true)
      end

      gaps = described_class.analyze
      chains = gaps.select { |g| g[:type] == :repeated_chain }
      expect(chains).not_to be_empty
      expect(chains.first[:chain]).to eq(%w[http.request.get consul.kv.put])
    end

    it 'detects frequent intents without dedicated patterns' do
      10.times { |i| Legion::MCP::Observer.record_intent("check service health #{i}", 'http.request.get') }

      gaps = described_class.analyze
      frequent = gaps.find { |g| g[:type] == :frequent_intent }
      expect(frequent).not_to be_nil
      expect(frequent[:tool]).to eq('http.request.get')
      expect(frequent[:count]).to eq(10)
    end

    it 'excludes intents that already have promoted patterns' do
      hash = Digest::SHA256.hexdigest('http.request.get')
      Legion::MCP::PatternStore.store(
        intent_hash: hash, intent_text: 'get', tool_chain: ['http.request.get'],
        confidence: 0.9, hit_count: 0, miss_count: 0, created_at: Time.now
      )

      10.times { Legion::MCP::Observer.record_intent('check health', 'http.request.get') }

      gaps = described_class.analyze
      frequent = gaps.select { |g| g[:type] == :frequent_intent }
      expect(frequent).to be_empty
    end

    it 'does not flag chains below threshold' do
      2.times do
        Legion::MCP::Observer.record(tool_name: 'a.tool', duration_ms: 10, success: true)
        Legion::MCP::Observer.record(tool_name: 'b.tool', duration_ms: 10, success: true)
      end

      chains = described_class.analyze.select { |g| g[:type] == :repeated_chain }
      expect(chains).to be_empty
    end
  end
end
