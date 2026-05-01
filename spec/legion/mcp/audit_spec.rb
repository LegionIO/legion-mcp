# frozen_string_literal: true

require 'spec_helper'
require 'legion/mcp'

RSpec.describe Legion::MCP::Audit do
  before do
    allow(Legion::Settings).to receive(:dig).and_return(nil)
  end

  describe '.transport_available?' do
    it 'returns false when Legion::Transport::Message is not defined' do
      expect(described_class.transport_available?).to be_falsey
    end
  end

  describe '.transport_connected?' do
    it 'returns false when transport is not connected' do
      expect(described_class.transport_connected?).to be(false)
    end

    it 'returns true when transport is connected' do
      allow(Legion::Settings).to receive(:dig).with(:transport, :connected).and_return(true)
      expect(described_class.transport_connected?).to be(true)
    end

    it 'returns false on error' do
      allow(Legion::Settings).to receive(:dig).with(:transport, :connected).and_raise(StandardError)
      expect(described_class.transport_connected?).to be(false)
    end
  end

  describe '.emit_tool_call' do
    it 'is a no-op when transport is not available' do
      expect { described_class.emit_tool_call(tool_name: 'test', status: :success) }.not_to raise_error
    end

    context 'with mocked transport' do
      let(:mock_message) { instance_double('message', publish: nil) }

      before do
        allow(described_class).to receive(:transport_available?).and_return(true)
        allow(described_class).to receive(:transport_connected?).and_return(true)

        stub_const('Legion::MCP::Transport::Messages::ToolCallEvent', Class.new do
          attr_reader :options

          def initialize(**options)
            @options = options
          end

          def publish
            { status: :accepted }
          end
        end)
      end

      it 'publishes a tool call event with the correct routing key' do
        event = {
          conversation_id: 'mcp_123',
          request_id:      'req_1',
          exchange_id:     'exch_abc',
          tool_call_id:    'call_def',
          tool_name:       'legion.list_tasks',
          status:          :success,
          duration_ms:     42.0,
          trace_id:        'aaa',
          timestamp:       '2026-04-30T00:00:00Z'
        }

        expect { described_class.emit_tool_call(**event) }.not_to raise_error
      end
    end
  end

  describe '.emit_client_call' do
    it 'is a no-op when transport is not available' do
      expect { described_class.emit_client_call(tool_name: 'test') }.not_to raise_error
    end
  end

  describe '.emit_governance' do
    it 'is a no-op when transport is not available' do
      expect { described_class.emit_governance(event: :tools_filtered) }.not_to raise_error
    end
  end

  describe 'ROUTING_KEYS' do
    it 'has correct routing keys' do
      expect(described_class::ROUTING_KEYS[:tool_call]).to eq('mcp.audit.tool_call')
      expect(described_class::ROUTING_KEYS[:client_call]).to eq('mcp.audit.client_call')
      expect(described_class::ROUTING_KEYS[:governance]).to eq('mcp.audit.governance')
    end
  end

  describe 'graceful degradation' do
    it 'does not raise when publish encounters an error' do
      allow(described_class).to receive(:transport_available?).and_return(true)
      allow(described_class).to receive(:transport_connected?).and_return(true)

      stub_const('Legion::MCP::Transport::Messages::ToolCallEvent', Class.new do
        def initialize(**_options)
          raise 'connection lost'
        end
      end)

      expect { described_class.emit_tool_call(tool_name: 'test') }.not_to raise_error
    end
  end
end
