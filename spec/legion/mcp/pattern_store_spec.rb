# frozen_string_literal: true

require 'spec_helper'
require 'legion/mcp/pattern_store'

RSpec.describe Legion::MCP::PatternStore do
  before { described_class.reset! }

  describe '.store and .lookup' do
    let(:pattern) do
      {
        intent_hash:          'abc123',
        intent_text:          'check deploy status',
        intent_vector:        nil,
        tool_chain:           ['legion.get_status'],
        response_template:    nil,
        confidence:           0.85,
        hit_count:            0,
        miss_count:           0,
        last_hit_at:          nil,
        created_at:           Time.now,
        context_requirements: nil
      }
    end

    it 'stores and retrieves a pattern by intent_hash' do
      described_class.store(pattern)
      result = described_class.lookup('abc123')
      expect(result).not_to be_nil
      expect(result[:intent_text]).to eq('check deploy status')
      expect(result[:tool_chain]).to eq(['legion.get_status'])
    end

    it 'returns nil for unknown intent_hash' do
      expect(described_class.lookup('nonexistent')).to be_nil
    end
  end

  describe '.record_hit' do
    it 'increments hit_count and updates last_hit_at' do
      described_class.store(intent_hash: 'h1', confidence: 0.9, hit_count: 0, miss_count: 0,
                            tool_chain: ['t'], intent_text: 'test', created_at: Time.now)
      described_class.record_hit('h1')
      p = described_class.lookup('h1')
      expect(p[:hit_count]).to eq(1)
      expect(p[:last_hit_at]).not_to be_nil
    end

    it 'increases confidence on hit' do
      described_class.store(intent_hash: 'h1', confidence: 0.9, hit_count: 0, miss_count: 0,
                            tool_chain: ['t'], intent_text: 'test', created_at: Time.now)
      described_class.record_hit('h1')
      expect(described_class.lookup('h1')[:confidence]).to be > 0.9
    end

    it 'resets miss_count on hit' do
      described_class.store(intent_hash: 'h1', confidence: 0.9, hit_count: 0, miss_count: 3,
                            tool_chain: ['t'], intent_text: 'test', created_at: Time.now)
      described_class.record_hit('h1')
      expect(described_class.lookup('h1')[:miss_count]).to eq(0)
    end
  end

  describe '.record_miss' do
    it 'increments miss_count and decreases confidence' do
      described_class.store(intent_hash: 'h1', confidence: 0.9, hit_count: 5, miss_count: 0,
                            tool_chain: ['t'], intent_text: 'test', created_at: Time.now)
      described_class.record_miss('h1')
      p = described_class.lookup('h1')
      expect(p[:miss_count]).to eq(1)
      expect(p[:confidence]).to be < 0.9
    end
  end

  describe '.promote_candidate' do
    it 'creates a new pattern with seeded confidence' do
      described_class.promote_candidate(intent_hash: 'new1', tool_chain: ['legion.get_status'],
                                        intent_text: 'check status')
      p = described_class.lookup('new1')
      expect(p).not_to be_nil
      expect(p[:confidence]).to eq(0.5)
      expect(p[:hit_count]).to eq(0)
    end
  end

  describe '.record_candidate' do
    it 'returns nil before threshold' do
      result = described_class.record_candidate(intent_hash: 'c1', tool_chain: ['t'],
                                                intent_text: 'test')
      expect(result).to be_nil
    end

    it 'returns promote signal at threshold' do
      2.times do
        described_class.record_candidate(intent_hash: 'c1', tool_chain: ['t'], intent_text: 'test')
      end
      result = described_class.record_candidate(intent_hash: 'c1', tool_chain: ['t'],
                                                intent_text: 'test')
      expect(result).not_to be_nil
      expect(result[:promote]).to be true
    end
  end

  describe '.lookup_semantic' do
    it 'finds pattern by cosine similarity' do
      vec = [0.1, 0.9, 0.3, 0.5]
      described_class.store(
        intent_hash: 'sem1', intent_text: 'check deploy',
        intent_vector: vec, tool_chain: ['legion.get_status'],
        confidence: 0.9, hit_count: 5, miss_count: 0,
        created_at: Time.now
      )

      similar_vec = [0.11, 0.89, 0.31, 0.49]
      result = described_class.lookup_semantic(similar_vec, threshold: 0.99)
      expect(result).not_to be_nil
      expect(result[:intent_text]).to eq('check deploy')
    end

    it 'returns nil when no vectors stored' do
      expect(described_class.lookup_semantic([0.1, 0.2])).to be_nil
    end

    it 'returns nil for nil input' do
      expect(described_class.lookup_semantic(nil)).to be_nil
    end
  end

  describe '.size and .stats' do
    it 'returns the number of stored patterns' do
      expect(described_class.size).to eq(0)
      described_class.store(intent_hash: 'a', confidence: 0.9, tool_chain: ['t'],
                            intent_text: 't', created_at: Time.now, hit_count: 0, miss_count: 0)
      expect(described_class.size).to eq(1)
    end

    it 'returns stats hash' do
      s = described_class.stats
      expect(s).to include(:size, :hit_rate, :avg_confidence)
    end
  end

  describe '.reset!' do
    it 'clears all patterns' do
      described_class.store(intent_hash: 'a', confidence: 0.9, tool_chain: ['t'],
                            intent_text: 't', created_at: Time.now, hit_count: 0, miss_count: 0)
      described_class.reset!
      expect(described_class.size).to eq(0)
    end
  end

  describe '.hydrate_from_l2' do
    it 'returns nil when L2 is unavailable' do
      expect(described_class.hydrate_from_l2).to be_nil
    end

    it 'loads all L2 patterns into L0 when available' do
      mock_table = []
      serialized = {
        intent_hash: 'hydrate1', intent_text: 'hydrate me',
        intent_vector: nil, tool_chain: '["test.tool"]',
        response_template: nil, confidence: 0.75,
        hit_count: 10, miss_count: 0, last_hit_at: nil,
        created_at: Time.now, context_requirements: nil
      }
      mock_table << serialized

      allow(described_class).to receive(:local_db_available?).and_return(true)
      allow(described_class).to receive(:ensure_local_table).and_return(mock_table)

      described_class.hydrate_from_l2
      expect(described_class.size).to eq(1)
      pattern = described_class.lookup('hydrate1')
      expect(pattern[:confidence]).to eq(0.75)
      expect(pattern[:tool_chain]).to eq(['test.tool'])
    end
  end

  describe '.decay_all' do
    before do
      described_class.store(
        intent_hash: 'decay_test', intent_text: 'test decay',
        intent_vector: nil, tool_chain: ['test.tool'],
        response_template: nil, confidence: 0.9,
        hit_count: 5, miss_count: 0, last_hit_at: Time.now,
        created_at: Time.now, context_requirements: nil
      )
    end

    it 'reduces confidence by decay factor' do
      described_class.decay_all(factor: 0.998)
      pattern = described_class.lookup('decay_test')
      expect(pattern[:confidence]).to be_within(0.001).of(0.9 * 0.998)
    end

    it 'archives patterns below threshold' do
      described_class.decay_all(factor: 0.01)
      expect(described_class.lookup('decay_test')).to be_nil
    end

    it 'does not archive patterns above threshold' do
      described_class.decay_all(factor: 0.998)
      expect(described_class.lookup('decay_test')).not_to be_nil
    end
  end

  describe '.candidates' do
    it 'returns the candidate buffer' do
      expect(described_class.candidates).to be_a(Hash)
    end
  end
end
