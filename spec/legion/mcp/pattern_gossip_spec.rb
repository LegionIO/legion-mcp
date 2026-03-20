# frozen_string_literal: true

require 'spec_helper'
require 'legion/mcp/pattern_gossip'

RSpec.describe Legion::MCP::PatternGossip do
  let(:pattern) do
    {
      intent_hash: 'gos1', intent_text: 'check health',
      tool_chain: ['http.request.get'], confidence: 0.9,
      hit_count: 50, miss_count: 2, created_at: Time.now
    }
  end

  describe '.announce' do
    it 'returns nil when transport unavailable' do
      expect(described_class.announce(pattern)).to be_nil
    end

    it 'publishes to AMQP when transport available' do
      transport_mod = Module.new do
        def self.connected?; true; end
      end
      stub_const('Legion::Transport', transport_mod)

      msg_instance = double(publish: true)
      msg_class = class_double('Legion::Transport::Messages::Dynamic', new: msg_instance)
      stub_const('Legion::Transport::Messages::Dynamic', msg_class)

      result = described_class.announce(pattern)
      expect(result[:published]).to be true
    end
  end

  describe '.receive' do
    it 'imports pattern from gossip message' do
      message = {
        pattern: {
          schema_version: '1.0',
          pattern_id: 'gossip1',
          intent: { description: 'check health', keywords: %w[check health] },
          capability_chain: [{ tool: 'http.request.get', params_template: {} }],
          response_template: nil,
          confidence: { suggested_initial: 0.4 },
          metadata: { source: 'org', sensitivity: 'public' }
        }
      }

      internal = described_class.receive(message)
      expect(internal[:intent_text]).to eq('check health')
      expect(internal[:confidence]).to be <= 0.4
    end

    it 'returns nil for invalid message' do
      expect(described_class.receive('invalid')).to be_nil
      expect(described_class.receive({})).to be_nil
    end
  end

  describe '.instance_id' do
    before { described_class.reset! }

    it 'returns a UUID' do
      expect(described_class.instance_id).to match(/\A[0-9a-f-]{36}\z/)
    end

    it 'is stable across calls' do
      id1 = described_class.instance_id
      id2 = described_class.instance_id
      expect(id1).to eq(id2)
    end
  end
end
