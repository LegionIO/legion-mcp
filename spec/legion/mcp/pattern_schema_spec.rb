# frozen_string_literal: true

require 'spec_helper'
require 'legion/mcp/pattern_schema'

RSpec.describe Legion::MCP::PatternSchema do
  let(:internal_pattern) do
    {
      intent_hash: 'abc123', intent_text: 'check health',
      tool_chain: ['http.request.get'], confidence: 0.9,
      response_template: '{{service}} is {{status}}',
      hit_count: 50, miss_count: 2, created_at: Time.now
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

  describe '.export' do
    it 'exports a pattern in v1 schema format' do
      exported = described_class.export(internal_pattern)
      expect(exported[:schema_version]).to eq('1.0')
      expect(exported[:intent][:description]).to eq('check health')
      expect(exported[:capability_chain]).to be_an(Array)
      expect(exported[:metadata][:sensitivity]).to eq('public')
    end

    it 'caps suggested_initial confidence at 0.5' do
      exported = described_class.export(internal_pattern)
      expect(exported[:confidence][:suggested_initial]).to be <= 0.5
    end

    it 'includes hit and miss counts' do
      exported = described_class.export(internal_pattern)
      expect(exported[:confidence][:source_hits]).to eq(50)
    end
  end

  describe '.import' do
    it 'converts v1 schema to internal pattern format' do
      internal = described_class.import(valid_v1_pattern)
      expect(internal[:intent_text]).to eq('check health')
      expect(internal[:tool_chain]).to eq(['http.request.get'])
      expect(internal[:confidence]).to eq(0.3)
    end

    it 'applies trust level confidence cap' do
      pattern = valid_v1_pattern.merge(confidence: { suggested_initial: 0.9 })
      internal = described_class.import(pattern, trust_level: :community)
      expect(internal[:confidence]).to eq(0.3)
    end

    it 'imports response template' do
      internal = described_class.import(valid_v1_pattern)
      expect(internal[:response_template]).to eq('{{status}}')
    end

    it 'starts with zero hit/miss counts' do
      internal = described_class.import(valid_v1_pattern)
      expect(internal[:hit_count]).to eq(0)
      expect(internal[:miss_count]).to eq(0)
    end
  end

  describe '.validate_schema' do
    it 'accepts valid v1 patterns' do
      expect(described_class.validate_schema(valid_v1_pattern)).to be true
    end

    it 'rejects patterns missing required fields' do
      expect(described_class.validate_schema({})).to be false
    end

    it 'rejects non-hash input' do
      expect(described_class.validate_schema('string')).to be false
    end
  end

  describe '.extract_keywords' do
    it 'extracts lowercase keywords from text' do
      keywords = described_class.extract_keywords('Check Service Health Status')
      expect(keywords).to include('check', 'service', 'health', 'status')
    end

    it 'returns empty array for nil' do
      expect(described_class.extract_keywords(nil)).to eq([])
    end
  end
end
