# frozen_string_literal: true

require 'spec_helper'
require 'legion/mcp'

RSpec.describe Legion::MCP::TracingContext do
  after { described_class.clear }

  describe '.generate_conversation_id' do
    it 'returns a string prefixed with mcp_' do
      id = described_class.generate_conversation_id
      expect(id).to match(/\Amcp_[0-9a-f-]{36}\z/)
    end

    it 'returns unique values' do
      ids = Array.new(10) { described_class.generate_conversation_id }
      expect(ids.uniq.size).to eq(10)
    end
  end

  describe '.generate_trace_id' do
    it 'returns a 32-character hex string' do
      id = described_class.generate_trace_id
      expect(id).to match(/\A[0-9a-f]{32}\z/)
    end
  end

  describe '.generate_request_id' do
    it 'uses the provided jsonrpc id' do
      expect(described_class.generate_request_id(42)).to eq('req_42')
    end

    it 'generates a fallback when jsonrpc id is nil' do
      expect(described_class.generate_request_id(nil)).to match(/\Areq_[0-9a-f]{16}\z/)
    end
  end

  describe '.generate_exchange_id' do
    it 'returns a prefixed hex string' do
      expect(described_class.generate_exchange_id).to match(/\Aexch_[0-9a-f]{24}\z/)
    end
  end

  describe '.generate_tool_call_id' do
    it 'returns a prefixed hex string' do
      expect(described_class.generate_tool_call_id).to match(/\Acall_[0-9a-f]{24}\z/)
    end
  end

  describe '.set and .current' do
    it 'stores all tracing IDs in Thread locals' do
      described_class.set(
        conversation_id: 'mcp_abc',
        request_id:      'req_1',
        exchange_id:     'exch_xyz',
        tool_call_id:    'call_def',
        trace_id:        'trace123'
      )

      ctx = described_class.current
      expect(ctx[:conversation_id]).to eq('mcp_abc')
      expect(ctx[:request_id]).to eq('req_1')
      expect(ctx[:exchange_id]).to eq('exch_xyz')
      expect(ctx[:tool_call_id]).to eq('call_def')
      expect(ctx[:trace_id]).to eq('trace123')
    end
  end

  describe '.clear' do
    it 'removes all tracing Thread locals' do
      described_class.set(
        conversation_id: 'mcp_abc',
        request_id:      'req_1',
        exchange_id:     'exch_xyz',
        tool_call_id:    'call_def',
        trace_id:        'trace123'
      )
      described_class.clear

      ctx = described_class.current
      expect(ctx.values).to all(be_nil)
    end
  end
end
