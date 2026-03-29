# frozen_string_literal: true

require 'spec_helper'

# Stub the actor base class if not available
unless defined?(Legion::Extensions::Actors::Every)
  module Legion
    module Extensions
      module Actors
        class Every
          def initialize(**); end
        end
      end
    end
  end
end

# Load the actor after stub
require_relative '../../../../lib/legion/mcp/actors/self_generate_cycle'

RSpec.describe Legion::MCP::Actor::SelfGenerateCycle do
  subject { described_class.new }

  describe '#time' do
    it 'defaults to 300 seconds' do
      expect(subject.time).to eq(300)
    end
  end

  describe '#enabled?' do
    it 'delegates to SelfGenerate.enabled?' do
      allow(Legion::MCP::SelfGenerate).to receive(:enabled?).and_return(false)
      expect(subject.enabled?).to be false
    end
  end

  describe '#runner_class' do
    it 'returns self.class' do
      expect(subject.runner_class).to eq(described_class)
    end
  end

  describe '#action' do
    it 'delegates to SelfGenerate.run_cycle' do
      allow(Legion::MCP::SelfGenerate).to receive(:run_cycle).and_return({ success: true, published: 0 })
      result = subject.action(nil)
      expect(result[:success]).to be true
    end
  end
end
