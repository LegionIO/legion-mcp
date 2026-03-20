# frozen_string_literal: true

require 'spec_helper'
require 'tempfile'
require 'legion/mcp/cold_start'

RSpec.describe Legion::MCP::ColdStart do
  before { Legion::MCP::PatternStore.reset! }

  describe '.load_community_patterns' do
    it 'imports patterns from file when store is empty' do
      file = Tempfile.new(['patterns', '.json'])
      file.write(::JSON.pretty_generate([{
        schema_version: '1.0',
        pattern_id: 'cold1',
        intent: { description: 'restart service', keywords: %w[restart service] },
        capability_chain: [{ tool: 'exec.run', params_template: {} }],
        response_template: nil,
        confidence: { suggested_initial: 0.3 },
        metadata: { source: 'community', sensitivity: 'public' }
      }]))
      file.close

      result = described_class.load_community_patterns(path: file.path)
      expect(result[:imported]).to eq(1)
    ensure
      file&.unlink
    end

    it 'skips when store already has patterns' do
      Legion::MCP::PatternStore.store(
        intent_hash: 'existing', intent_text: 'existing',
        tool_chain: ['test'], confidence: 0.9,
        hit_count: 1, miss_count: 0, created_at: Time.now
      )

      result = described_class.load_community_patterns(path: '/tmp/fake.json')
      expect(result).to eq({ skipped: true, reason: 'store not empty' })
    end

    it 'skips when no path configured' do
      result = described_class.load_community_patterns
      expect(result).to eq({ skipped: true, reason: 'no path configured' })
    end

    it 'returns error hash on failure' do
      result = described_class.load_community_patterns(path: '/nonexistent/patterns.json')
      expect(result[:error]).to be_a(String)
      expect(result[:imported]).to eq(0)
    end
  end

  describe '.configured_path' do
    it 'returns nil when Legion::Settings not defined' do
      hide_const('Legion::Settings')
      expect(described_class.configured_path).to be_nil
    end

    it 'reads from settings when available' do
      allow(Legion::Settings).to receive(:dig)
        .with(:mcp, :cold_start, :patterns_path)
        .and_return('/opt/legion/community_patterns.json')

      expect(described_class.configured_path).to eq('/opt/legion/community_patterns.json')
    end
  end
end
