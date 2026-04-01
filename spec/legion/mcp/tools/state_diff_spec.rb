# frozen_string_literal: true

require 'spec_helper'
require 'legion/mcp'

RSpec.describe Legion::MCP::Tools::StateDiff do
  before do
    Legion::MCP::StateTracker.reset!
    allow(Legion::Settings).to receive(:dig).and_return(nil)
  end

  describe '.call' do
    context 'with no arguments' do
      it 'returns current state with timestamp' do
        response = described_class.call
        expect(response).to be_a(MCP::Tool::Response)
        expect(response.error?).to be false
        data = Legion::JSON.load(response.content.first[:text])
        expect(data).to have_key(:tool_count)
        expect(data).to have_key(:timestamp)
      end
    end

    context 'with snapshot: true' do
      it 'takes a snapshot and returns it' do
        response = described_class.call(snapshot: true)
        expect(response.error?).to be false
        data = Legion::JSON.load(response.content.first[:text])
        expect(data).to have_key(:state)
        expect(data).to have_key(:timestamp)
      end
    end

    context 'with since: timestamp' do
      it 'returns diff against baseline' do
        snap = Legion::MCP::StateTracker.snapshot
        response = described_class.call(since: snap[:timestamp])
        expect(response.error?).to be false
        data = Legion::JSON.load(response.content.first[:text])
        expect(data).to have_key(:changes)
      end

      it 'returns full_state when no baseline exists for the timestamp' do
        response = described_class.call(since: '2099-01-01T00:00:00Z')
        expect(response.error?).to be false
        data = Legion::JSON.load(response.content.first[:text])
        expect(data).to have_key(:full_state)
      end
    end

    context 'when an error occurs' do
      before do
        allow(Legion::MCP::StateTracker).to receive(:collect_state).and_raise(StandardError, 'state error')
      end

      it 'returns error response' do
        response = described_class.call
        expect(response.error?).to be true
        data = Legion::JSON.load(response.content.first[:text])
        expect(data[:error]).to include('state error')
      end
    end
  end
end
