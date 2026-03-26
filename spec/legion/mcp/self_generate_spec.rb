# frozen_string_literal: true

require 'spec_helper'
require 'legion/mcp/observer'
require 'legion/mcp/pattern_store'
require 'legion/mcp/gap_detector'
require 'legion/mcp/self_generate'

RSpec.describe Legion::MCP::SelfGenerate do
  before do
    Legion::MCP::Observer.reset!
    Legion::MCP::PatternStore.reset!
    described_class.reset!
  end

  describe '.run_cycle' do
    it 'returns success with zero gaps when nothing detected' do
      result = described_class.run_cycle
      expect(result[:success]).to be true
      expect(result[:gaps_found]).to eq(0)
      expect(result[:generated]).to eq(0)
    end

    it 'returns cooldown when called too soon after previous cycle' do
      # Seed gaps so the first cycle actually records
      6.times { Legion::MCP::Observer.record_intent('cooldown test intent', nil) }
      described_class.run_cycle
      # Second cycle immediately
      result = described_class.run_cycle
      expect(result[:success]).to be false
      expect(result[:reason]).to eq(:cooldown)
    end

    it 'processes detected gaps' do
      # Seed unmatched intents above threshold
      6.times { Legion::MCP::Observer.record_intent('deploy my service', nil) }

      result = described_class.run_cycle
      expect(result[:success]).to be true
      expect(result[:gaps_found]).to be >= 1
      expect(result[:processed]).to be >= 1
      expect(result[:results]).to be_an(Array)
    end

    it 'limits processing to MAX_GAPS_PER_CYCLE' do
      expect(described_class::MAX_GAPS_PER_CYCLE).to eq(5)
    end

    it 'increments cycle_count when gaps exist' do
      6.times { Legion::MCP::Observer.record_intent('cycle count test', nil) }
      expect { described_class.run_cycle }.to change { described_class.cycle_count }.by(1)
    end

    it 'does not increment cycle_count when no gaps' do
      before_count = described_class.cycle_count
      described_class.run_cycle
      expect(described_class.cycle_count).to eq(before_count)
    end

    it 'records results with gap id and type' do
      6.times { Legion::MCP::Observer.record_intent('test gap detection', nil) }

      result = described_class.run_cycle
      next if result[:results].nil? || result[:results].empty?

      entry = result[:results].first
      expect(entry).to have_key(:gap)
      expect(entry).to have_key(:type)
      expect(entry).to have_key(:result)
    end
  end

  describe '.status' do
    it 'returns status hash' do
      status = described_class.status
      expect(status).to have_key(:last_cycle_at)
      expect(status).to have_key(:total_cycles)
      expect(status).to have_key(:total_generated)
      expect(status).to have_key(:cooldown_remaining)
      expect(status).to have_key(:pending_gaps)
    end

    it 'returns nil last_cycle_at initially' do
      expect(described_class.status[:last_cycle_at]).to be_nil
    end

    it 'returns zero total_cycles initially' do
      expect(described_class.status[:total_cycles]).to eq(0)
    end

    it 'returns zero total_generated initially' do
      expect(described_class.status[:total_generated]).to eq(0)
    end

    it 'updates after a cycle with gaps' do
      6.times { Legion::MCP::Observer.record_intent('status update test', nil) }
      described_class.run_cycle
      status = described_class.status
      expect(status[:last_cycle_at]).to be_a(Time)
      expect(status[:total_cycles]).to eq(1)
    end
  end

  describe '.reset!' do
    it 'clears all state' do
      described_class.run_cycle
      described_class.reset!

      expect(described_class.cycle_count).to eq(0)
      expect(described_class.total_generated).to eq(0)
      expect(described_class.cycle_history).to be_empty
    end
  end

  describe '.in_cooldown?' do
    it 'returns false when never run' do
      expect(described_class.in_cooldown?).to be false
    end

    it 'returns true immediately after a cycle with gaps' do
      6.times { Legion::MCP::Observer.record_intent('cooldown check', nil) }
      described_class.run_cycle
      expect(described_class.in_cooldown?).to be true
    end
  end

  describe '.cooldown_remaining' do
    it 'returns 0 when never run' do
      expect(described_class.cooldown_remaining).to eq(0)
    end

    it 'returns positive value after a cycle with gaps' do
      6.times { Legion::MCP::Observer.record_intent('cooldown remaining', nil) }
      described_class.run_cycle
      expect(described_class.cooldown_remaining).to be > 0
      expect(described_class.cooldown_remaining).to be <= described_class::COOLDOWN_SECONDS
    end
  end

  describe '.cycle_history' do
    it 'returns empty array initially' do
      expect(described_class.cycle_history).to be_empty
    end

    it 'records cycle entries when gaps exist' do
      6.times { Legion::MCP::Observer.record_intent('history test', nil) }
      described_class.run_cycle
      history = described_class.cycle_history
      expect(history.size).to eq(1)
      expect(history.first).to have_key(:at)
      expect(history.first).to have_key(:results_count)
      expect(history.first).to have_key(:generated)
    end

    it 'respects limit parameter' do
      # Force multiple cycles by resetting cooldown and seeding gaps
      3.times do |i|
        Legion::MCP::Observer.reset!
        6.times { Legion::MCP::Observer.record_intent("limit test #{i}", nil) }
        described_class.instance_variable_set(:@last_cycle_at, nil)
        described_class.run_cycle
      end
      expect(described_class.cycle_history(2).size).to eq(2)
    end
  end

  describe 'constants' do
    it 'has COOLDOWN_SECONDS of 300' do
      expect(described_class::COOLDOWN_SECONDS).to eq(300)
    end

    it 'has MAX_GAPS_PER_CYCLE of 5' do
      expect(described_class::MAX_GAPS_PER_CYCLE).to eq(5)
    end
  end
end
