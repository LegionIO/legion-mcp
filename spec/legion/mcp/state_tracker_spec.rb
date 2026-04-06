# frozen_string_literal: true

require 'spec_helper'
require 'legion/mcp'

RSpec.describe Legion::MCP::StateTracker do
  before do
    described_class.reset!
    allow(Legion::Settings).to receive(:dig).and_return(nil)
  end

  describe '.collect_state' do
    it 'returns a hash with tool_count' do
      state = described_class.collect_state
      expect(state[:tool_count]).to be_a(Integer)
      expect(state[:tool_count]).to be >= 6
    end

    it 'includes observer_stats' do
      state = described_class.collect_state
      expect(state).to have_key(:observer_stats)
    end

    it 'includes pattern_count' do
      state = described_class.collect_state
      expect(state).to have_key(:pattern_count)
    end

    it 'includes extensions count' do
      state = described_class.collect_state
      expect(state).to have_key(:extensions)
    end
  end

  describe '.snapshot' do
    it 'returns state with timestamp' do
      result = described_class.snapshot
      expect(result[:state]).to have_key(:tool_count)
      expect(result[:timestamp]).to be_a(String)
    end

    it 'stores the snapshot for later diff' do
      described_class.snapshot
      expect(described_class.send(:snapshots).size).to eq(1)
    end

    it 'limits snapshots to MAX_SNAPSHOTS' do
      (described_class::MAX_SNAPSHOTS + 5).times { described_class.snapshot }
      expect(described_class.send(:snapshots).size).to eq(described_class::MAX_SNAPSHOTS)
    end
  end

  describe '.diff' do
    it 'returns full_state when no baseline exists' do
      result = described_class.diff(since: Time.now.iso8601)
      expect(result).to have_key(:full_state)
      expect(result[:reason]).to include('no baseline')
    end

    it 'returns changes when baseline exists' do
      snap = described_class.snapshot

      # Record some observer activity to change state
      Legion::MCP::Observer.record(tool_name: 'test', duration_ms: 10, success: true)

      result = described_class.diff(since: snap[:timestamp])
      expect(result).to have_key(:changes)
      expect(result).to have_key(:since)
      expect(result).to have_key(:timestamp)
    end

    it 'returns empty changes when state is unchanged' do
      snap = described_class.snapshot
      result = described_class.diff(since: snap[:timestamp])
      expect(result[:changes]).to eq({})
    end

    it 'returns error for invalid timestamp' do
      result = described_class.diff(since: 'not-a-date')
      expect(result[:error]).to eq('invalid timestamp')
    end
  end

  describe '.compute_diff' do
    it 'returns empty hash for identical states' do
      state = { a: 1, b: 'hello' }
      expect(described_class.compute_diff(state, state)).to eq({})
    end

    it 'returns before/after for changed values' do
      old_state = { a: 1 }
      new_state = { a: 2 }
      diff = described_class.compute_diff(old_state, new_state)
      expect(diff[:a]).to eq({ before: 1, after: 2 })
    end

    it 'handles nested hash diffs' do
      old_state = { stats: { calls: 5, errors: 0 } }
      new_state = { stats: { calls: 10, errors: 0 } }
      diff = described_class.compute_diff(old_state, new_state)
      expect(diff[:stats][:calls]).to eq({ before: 5, after: 10 })
    end

    it 'handles new keys' do
      old_state = { a: 1 }
      new_state = { a: 1, b: 2 }
      diff = described_class.compute_diff(old_state, new_state)
      expect(diff[:b]).to eq({ before: nil, after: 2 })
    end
  end

  describe '.reset!' do
    it 'clears all snapshots' do
      described_class.snapshot
      described_class.reset!
      expect(described_class.send(:snapshots)).to be_empty
    end
  end
end
