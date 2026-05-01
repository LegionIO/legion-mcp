# frozen_string_literal: true

require 'spec_helper'
require 'legion/mcp/observer'
require 'legion/mcp/patterns/store'
require 'legion/mcp/gap_detector'
require 'legion/mcp/self_generate'

RSpec.describe Legion::MCP::SelfGenerate do
  before do
    Legion::MCP::Observer.reset!
    Legion::MCP::Patterns::Store.reset!
    described_class.reset!
  end

  describe '.enabled?' do
    it 'returns false by default' do
      allow(Legion::Settings).to receive(:dig).and_return(nil)
      expect(described_class.enabled?).to be false
    end

    it 'returns true when settings enable it' do
      allow(Legion::Settings).to receive(:dig).with(:codegen, :self_generate, :enabled).and_return(true)
      expect(described_class.enabled?).to be true
    end
  end

  describe '.run_cycle' do
    it 'returns disabled when not enabled' do
      allow(Legion::Settings).to receive(:dig).and_return(nil)
      result = described_class.run_cycle
      expect(result[:success]).to be false
      expect(result[:reason]).to eq(:disabled)
    end

    context 'when enabled' do
      before do
        allow(Legion::Settings).to receive(:dig).and_return(nil)
        allow(Legion::Settings).to receive(:dig).with(:codegen, :self_generate, :enabled).and_return(true)
        allow(Legion::Settings).to receive(:dig).with(:codegen, :self_generate, :cooldown_seconds).and_return(nil)
        allow(Legion::Settings).to receive(:dig).with(:codegen, :self_generate, :max_gaps_per_cycle).and_return(nil)
      end

      it 'returns success with zero gaps when nothing detected' do
        result = described_class.run_cycle
        expect(result[:success]).to be true
        expect(result[:gaps_found]).to eq(0)
        expect(result[:published]).to eq(0)
      end

      it 'returns cooldown when called too soon after previous cycle' do
        allow(described_class).to receive(:publish_gap).and_return(true)
        6.times { Legion::MCP::Observer.record_intent('cooldown test intent', nil) }
        described_class.run_cycle
        result = described_class.run_cycle
        expect(result[:success]).to be false
        expect(result[:reason]).to eq(:cooldown)
      end

      it 'publishes detected gaps' do
        6.times { Legion::MCP::Observer.record_intent('deploy my service', nil) }
        expect(described_class).to receive(:publish_gap).at_least(:once)
        described_class.run_cycle
      end

      it 'limits processing to max_gaps_per_cycle' do
        expect(described_class.send(:max_gaps_per_cycle)).to eq(5)
      end

      it 'reads max_gaps_per_cycle from Settings' do
        allow(Legion::Settings).to receive(:dig).with(:codegen, :self_generate, :max_gaps_per_cycle).and_return(3)
        expect(described_class.send(:max_gaps_per_cycle)).to eq(3)
      end

      it 'increments cycle_count when gaps exist and publish succeeds' do
        allow(described_class).to receive(:publish_gap).and_return(true)
        6.times { Legion::MCP::Observer.record_intent('cycle count test', nil) }
        expect { described_class.run_cycle }.to change { described_class.cycle_count }.by(1)
      end
    end
  end

  describe '.publish_gap' do
    it 'does not raise when Transport is unavailable' do
      expect { described_class.publish_gap({ id: 'g1', type: :test }) }.not_to raise_error
    end
  end

  describe '.status' do
    it 'returns status hash' do
      status = described_class.status
      expect(status).to have_key(:last_cycle_at)
      expect(status).to have_key(:total_cycles)
      expect(status).to have_key(:total_published)
      expect(status).to have_key(:cooldown_remaining)
      expect(status).to have_key(:pending_gaps)
    end
  end

  describe '.reset!' do
    it 'clears all state' do
      described_class.reset!
      expect(described_class.cycle_count).to eq(0)
      expect(described_class.total_published).to eq(0)
      expect(described_class.cycle_history).to be_empty
    end
  end

  describe '.in_cooldown?' do
    it 'returns false when never run' do
      expect(described_class.in_cooldown?).to be false
    end
  end

  describe '.cooldown_remaining' do
    it 'returns 0 when never run' do
      expect(described_class.cooldown_remaining).to eq(0)
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
