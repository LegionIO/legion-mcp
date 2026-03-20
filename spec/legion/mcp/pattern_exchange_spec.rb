# frozen_string_literal: true

require 'spec_helper'
require 'legion/mcp/pattern_store'
require 'legion/mcp/pattern_exchange'

RSpec.describe Legion::MCP::PatternExchange do
  let(:valid_pattern) do
    {
      intent_hash: 'exp1', intent_text: 'check health',
      tool_chain: ['http.request.get'], confidence: 0.9,
      hit_count: 50, miss_count: 2, created_at: Time.now
    }
  end

  let(:low_conf_pattern) do
    {
      intent_hash: 'exp2', intent_text: 'low conf',
      tool_chain: ['test'], confidence: 0.2,
      hit_count: 1, miss_count: 5, created_at: Time.now
    }
  end

  let(:valid_v1_pattern) do
    {
      schema_version: '1.0',
      pattern_id: 'sha256abc',
      intent: { description: 'check health', keywords: %w[check health] },
      capability_chain: [{ tool: 'http.request.get', params_template: {} }],
      response_template: { engine: 'mustache', template: '{{status}}' },
      confidence: { suggested_initial: 0.3 },
      metadata: { source: 'community', sensitivity: 'public' }
    }
  end

  before { Legion::MCP::PatternStore.reset! }

  describe '.export_all' do
    it 'exports patterns above confidence threshold' do
      Legion::MCP::PatternStore.store(valid_pattern)
      Legion::MCP::PatternStore.store(low_conf_pattern)

      exported = described_class.export_all(min_confidence: 0.5)
      expect(exported.size).to eq(1)
      expect(exported.first[:schema_version]).to eq('1.0')
    end
  end

  describe '.import_all' do
    it 'imports patterns with trust-adjusted confidence' do
      result = described_class.import_all([valid_v1_pattern], trust_level: :community)
      expect(result[:imported]).to eq(1)

      stored = Legion::MCP::PatternStore.lookup('sha256abc')
      expect(stored[:confidence]).to eq(0.3)
    end

    it 'skips duplicate patterns' do
      described_class.import_all([valid_v1_pattern])
      result = described_class.import_all([valid_v1_pattern])
      expect(result[:skipped]).to eq(1)
      expect(result[:imported]).to eq(0)
    end
  end

  describe '.export_to_file / .import_from_file' do
    let(:path) { '/tmp/test_tbi_patterns.json' }

    after { File.delete(path) if File.exist?(path) }

    it 'round-trips through JSON file' do
      Legion::MCP::PatternStore.store(valid_pattern)

      described_class.export_to_file(path)
      Legion::MCP::PatternStore.reset!
      result = described_class.import_from_file(path, trust_level: :org)

      expect(result[:imported]).to eq(1)
      expect(Legion::MCP::PatternStore.size).to eq(1)
    end
  end
end
