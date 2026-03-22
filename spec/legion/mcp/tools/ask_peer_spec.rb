# frozen_string_literal: true

require 'spec_helper'
require 'legion/mcp'

RSpec.describe Legion::MCP::Tools::AskPeer do
  let(:mock_client) { double('client') }
  let(:rpc_result)  { { status: 'ok', answer: 'pong' } }

  describe '.call' do
    context 'when lex-mesh is not available' do
      before do
        allow(described_class).to receive(:mesh_available?).and_return(false)
      end

      it 'returns an error response' do
        response = described_class.call(to: 'agent-1', query: 'ping')
        expect(response).to be_a(MCP::Tool::Response)
        expect(response.error?).to be true
      end

      it 'error message mentions lex-mesh' do
        response = described_class.call(to: 'agent-1', query: 'ping')
        data = Legion::JSON.load(response.content.first[:text])
        expect(data[:error]).to include('lex-mesh')
      end
    end

    context 'when lex-mesh is available' do
      before do
        allow(described_class).to receive(:mesh_available?).and_return(true)
        stub_const('Legion::Extensions::Mesh::Client', Class.new)
        allow(Legion::Extensions::Mesh::Client).to receive(:new).and_return(mock_client)
        allow(described_class).to receive(:mesh_client).and_return(mock_client)
      end

      it 'returns a successful response' do
        allow(mock_client).to receive(:request_task).and_return(rpc_result)
        response = described_class.call(to: 'agent-1', query: 'ping')
        expect(response.error?).to be false
      end

      it 'calls request_task with correct args' do
        expect(mock_client).to receive(:request_task).with(
          from:    'legion.mcp',
          to:      'agent-1',
          task:    'query',
          payload: { query: 'ping' },
          timeout: 30
        ).and_return(rpc_result)
        described_class.call(to: 'agent-1', query: 'ping')
      end

      it 'passes custom timeout' do
        expect(mock_client).to receive(:request_task).with(
          from:    'legion.mcp',
          to:      'agent-1',
          task:    'query',
          payload: { query: 'ping' },
          timeout: 60
        ).and_return(rpc_result)
        described_class.call(to: 'agent-1', query: 'ping', timeout: 60)
      end

      it 'response contains result data' do
        allow(mock_client).to receive(:request_task).and_return(rpc_result)
        response = described_class.call(to: 'agent-1', query: 'ping')
        data = Legion::JSON.load(response.content.first[:text])
        expect(data[:status]).to eq('ok')
      end

      it 'returns error response on exception' do
        allow(mock_client).to receive(:request_task).and_raise(StandardError, 'timeout')
        response = described_class.call(to: 'agent-1', query: 'ping')
        expect(response.error?).to be true
        data = Legion::JSON.load(response.content.first[:text])
        expect(data[:error]).to include('timeout')
      end
    end
  end
end
