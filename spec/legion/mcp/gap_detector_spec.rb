# frozen_string_literal: true

require 'spec_helper'
require 'legion/mcp/observer'
require 'legion/mcp/patterns/store'
require 'legion/mcp/gap_detector'

RSpec.describe Legion::MCP::GapDetector do
  before do
    Legion::MCP::Observer.reset!
    Legion::MCP::Patterns::Store.reset!
  end

  # ---------------------------------------------------------------------------
  # detect_gaps
  # ---------------------------------------------------------------------------
  describe '.detect_gaps' do
    it 'returns an empty array when no data' do
      expect(described_class.detect_gaps).to eq([])
    end

    it 'returns an array' do
      expect(described_class.detect_gaps).to be_an(Array)
    end

    it 'deduplicates by id across detection methods' do
      # Seed a stale candidate that has count >= 2
      Legion::MCP::Patterns::Store.record_candidate(
        intent_hash: 'aabbccdd1234', tool_chain: ['http.get'], intent_text: 'ping service', threshold: 999
      )
      Legion::MCP::Patterns::Store.record_candidate(
        intent_hash: 'aabbccdd1234', tool_chain: ['http.get'], intent_text: 'ping service', threshold: 999
      )
      gaps = described_class.detect_gaps
      ids = gaps.map { |g| g[:id] }
      expect(ids.uniq.size).to eq(ids.size)
    end

    it 'limits output to MAX_GAPS' do
      # Create many unmatched intents
      (described_class::MAX_GAPS + 5).times do |i|
        described_class::GAP_INTENT_THRESHOLD.times do
          Legion::MCP::Observer.record_intent("unique query number #{i}", nil)
        end
      end
      gaps = described_class.detect_gaps
      expect(gaps.size).to be <= described_class::MAX_GAPS
    end
  end

  # ---------------------------------------------------------------------------
  # detect_unmatched_intents
  # ---------------------------------------------------------------------------
  describe '.detect_unmatched_intents' do
    it 'returns empty when Observer not defined' do
      hide_const('Legion::MCP::Observer')
      expect(described_class.detect_unmatched_intents).to eq([])
    end

    it 'returns empty when no unmatched intents exist' do
      5.times { Legion::MCP::Observer.record_intent('check status', 'legion.get_status') }
      expect(described_class.detect_unmatched_intents).to eq([])
    end

    it 'finds intents with nil matched_tool above threshold' do
      described_class::GAP_INTENT_THRESHOLD.times do
        Legion::MCP::Observer.record_intent('unknown command', nil)
      end
      gaps = described_class.detect_unmatched_intents
      expect(gaps).not_to be_empty
      expect(gaps.first[:type]).to eq(:unmatched_intent)
      expect(gaps.first[:intent]).to eq('unknown command')
    end

    it 'finds intents with matched_tool == "none" above threshold' do
      described_class::GAP_INTENT_THRESHOLD.times do
        Legion::MCP::Observer.record_intent('do the thing', 'none')
      end
      gaps = described_class.detect_unmatched_intents
      expect(gaps).not_to be_empty
      expect(gaps.first[:intent]).to eq('do the thing')
    end

    it 'ignores intents below threshold' do
      (described_class::GAP_INTENT_THRESHOLD - 1).times do
        Legion::MCP::Observer.record_intent('rare query', nil)
      end
      expect(described_class.detect_unmatched_intents).to be_empty
    end

    it 'normalizes intent text before grouping' do
      described_class::GAP_INTENT_THRESHOLD.times do |i|
        # Mix of spacing/case that should all normalize to the same intent
        text = i.even? ? 'FIND  THE  FILE' : 'find the file'
        Legion::MCP::Observer.record_intent(text, nil)
      end
      gaps = described_class.detect_unmatched_intents
      expect(gaps.size).to eq(1)
    end

    it 'includes occurrences count in gap' do
      described_class::GAP_INTENT_THRESHOLD.times do
        Legion::MCP::Observer.record_intent('missing tool intent', nil)
      end
      gap = described_class.detect_unmatched_intents.first
      expect(gap[:occurrences]).to eq(described_class::GAP_INTENT_THRESHOLD)
    end

    it 'includes id, first_seen, last_seen, priority in gap' do
      described_class::GAP_INTENT_THRESHOLD.times do
        Legion::MCP::Observer.record_intent('orphan request', nil)
      end
      gap = described_class.detect_unmatched_intents.first
      expect(gap[:id]).to start_with('unmatched:')
      expect(gap[:first_seen]).to be_a(Time)
      expect(gap[:last_seen]).to be_a(Time)
      expect(gap[:priority]).to be_a(Float)
    end
  end

  # ---------------------------------------------------------------------------
  # detect_high_failure_tools
  # ---------------------------------------------------------------------------
  describe '.detect_high_failure_tools' do
    it 'returns empty when Observer not defined' do
      hide_const('Legion::MCP::Observer')
      expect(described_class.detect_high_failure_tools).to eq([])
    end

    it 'returns empty when no tools have high failure rates' do
      10.times { Legion::MCP::Observer.record(tool_name: 'good.tool', duration_ms: 10, success: true) }
      expect(described_class.detect_high_failure_tools).to be_empty
    end

    it 'finds tools above failure rate threshold' do
      5.times { Legion::MCP::Observer.record(tool_name: 'flaky.tool', duration_ms: 10, success: false, error: 'boom') }
      5.times { Legion::MCP::Observer.record(tool_name: 'flaky.tool', duration_ms: 10, success: false, error: 'boom') }
      gaps = described_class.detect_high_failure_tools
      expect(gaps).not_to be_empty
      expect(gaps.first[:type]).to eq(:high_failure_tool)
      expect(gaps.first[:tool_name]).to eq('flaky.tool')
    end

    it 'ignores tools with fewer than 5 calls' do
      3.times { Legion::MCP::Observer.record(tool_name: 'rare.tool', duration_ms: 10, success: false) }
      expect(described_class.detect_high_failure_tools).to be_empty
    end

    it 'ignores tools below failure rate threshold' do
      8.times { Legion::MCP::Observer.record(tool_name: 'mostly.good', duration_ms: 10, success: true) }
      2.times { Legion::MCP::Observer.record(tool_name: 'mostly.good', duration_ms: 10, success: false) }
      expect(described_class.detect_high_failure_tools).to be_empty
    end

    it 'includes failure_rate, call_count, failure_count in gap' do
      5.times { Legion::MCP::Observer.record(tool_name: 'bad.tool', duration_ms: 10, success: false, error: 'err') }
      5.times { Legion::MCP::Observer.record(tool_name: 'bad.tool', duration_ms: 10, success: true) }
      gap = described_class.detect_high_failure_tools.first
      expect(gap[:failure_rate]).to eq(0.5)
      expect(gap[:call_count]).to eq(10)
      expect(gap[:failure_count]).to eq(5)
    end

    it 'includes id starting with "failing:"' do
      6.times { Legion::MCP::Observer.record(tool_name: 'err.tool', duration_ms: 10, success: false) }
      gap = described_class.detect_high_failure_tools.first
      expect(gap[:id]).to start_with('failing:')
    end
  end

  # ---------------------------------------------------------------------------
  # detect_stale_candidates
  # ---------------------------------------------------------------------------
  describe '.detect_stale_candidates' do
    it 'returns empty when PatternStore not defined' do
      hide_const('Legion::MCP::Patterns::Store')
      expect(described_class.detect_stale_candidates).to eq([])
    end

    it 'returns empty when no candidates exist' do
      expect(described_class.detect_stale_candidates).to be_empty
    end

    it 'finds candidates with count >= 2 that never promoted' do
      hash = Digest::SHA256.hexdigest('find me something')
      # record_candidate won't promote at a high threshold
      2.times do
        Legion::MCP::Patterns::Store.record_candidate(
          intent_hash: hash, tool_chain: ['search.runner'], intent_text: 'find me something', threshold: 999
        )
      end
      gaps = described_class.detect_stale_candidates
      expect(gaps).not_to be_empty
      expect(gaps.first[:type]).to eq(:stale_candidate)
    end

    it 'ignores candidates with count < 2' do
      hash = Digest::SHA256.hexdigest('lonely intent')
      Legion::MCP::Patterns::Store.record_candidate(
        intent_hash: hash, tool_chain: ['some.runner'], intent_text: 'lonely intent', threshold: 999
      )
      expect(described_class.detect_stale_candidates).to be_empty
    end

    it 'includes intent_text, tool_chain, observation_count in gap' do
      hash = Digest::SHA256.hexdigest('stale candidate text')
      3.times do
        Legion::MCP::Patterns::Store.record_candidate(
          intent_hash: hash, tool_chain: ['test.runner'], intent_text: 'stale candidate text', threshold: 999
        )
      end
      gap = described_class.detect_stale_candidates.first
      expect(gap[:intent_text]).to eq('stale candidate text')
      expect(gap[:tool_chain]).to eq(['test.runner'])
      expect(gap[:observation_count]).to eq(3)
    end

    it 'includes id starting with "stale:"' do
      hash = Digest::SHA256.hexdigest('another stale')
      2.times do
        Legion::MCP::Patterns::Store.record_candidate(
          intent_hash: hash, tool_chain: ['x.runner'], intent_text: 'another stale', threshold: 999
        )
      end
      gap = described_class.detect_stale_candidates.first
      expect(gap[:id]).to start_with('stale:')
    end
  end

  # ---------------------------------------------------------------------------
  # calculate_priority
  # ---------------------------------------------------------------------------
  describe '.calculate_priority' do
    it 'returns a float' do
      expect(described_class.calculate_priority(5, :unmatched)).to be_a(Float)
    end

    it 'clamps to maximum 1.0' do
      expect(described_class.calculate_priority(1000, :unmatched)).to eq(1.0)
    end

    it 'clamps to minimum 0.0' do
      expect(described_class.calculate_priority(0, :unknown)).to be >= 0.0
    end

    it 'unmatched base is higher than failure base' do
      p_unmatched = described_class.calculate_priority(1, :unmatched)
      p_failure   = described_class.calculate_priority(1, :failure)
      expect(p_unmatched).to be > p_failure
    end

    it 'failure base is higher than stale base' do
      p_failure = described_class.calculate_priority(1, :failure)
      p_stale   = described_class.calculate_priority(1, :stale)
      expect(p_failure).to be > p_stale
    end

    it 'higher count yields higher priority (up to cap)' do
      low  = described_class.calculate_priority(1, :stale)
      high = described_class.calculate_priority(9, :stale)
      expect(high).to be >= low
    end
  end

  # ---------------------------------------------------------------------------
  # normalize_intent
  # ---------------------------------------------------------------------------
  describe '.normalize_intent' do
    it 'strips leading and trailing whitespace' do
      expect(described_class.normalize_intent('  hello  ')).to eq('hello')
    end

    it 'downcases text' do
      expect(described_class.normalize_intent('HELLO WORLD')).to eq('hello world')
    end

    it 'collapses multiple spaces' do
      expect(described_class.normalize_intent('hello   world')).to eq('hello world')
    end

    it 'handles nil gracefully' do
      expect(described_class.normalize_intent(nil)).to eq('')
    end
  end
end
