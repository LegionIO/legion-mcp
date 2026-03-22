# frozen_string_literal: true

require 'spec_helper'
require 'legion/mcp'

RSpec.describe Legion::MCP::Tools::BroadcastPeers do
  let(:mock_client)      { double('client') }
  let(:broadcast_result) { { delivered_count: 5 } }

  describe '.call' do
    context 'when lex-mesh is not available' do
      before do
        allow(described_class).to receive(:mesh_available?).and_return(false)
      end

      it 'returns an error response' do
        response = described_class.call(message: 'system update')
        expect(response).to be_a(MCP::Tool::Response)
        expect(response.error?).to be true
      end

      it 'error message mentions lex-mesh' do
        response = described_class.call(message: 'system update')
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
        allow(mock_client).to receive(:send_message).and_return(broadcast_result)
        response = described_class.call(message: 'system update')
        expect(response.error?).to be false
      end

      it 'uses broadcast pattern when no capability given' do
        expect(mock_client).to receive(:send_message).with(
          from:    'legion.mcp',
          to:      :all,
          pattern: :broadcast,
          payload: { message: 'system update' }
        ).and_return(broadcast_result)
        described_class.call(message: 'system update')
      end

      it 'uses multicast pattern when capability is given' do
        expect(mock_client).to receive(:send_message).with(
          from:    'legion.mcp',
          to:      'transform',
          pattern: :multicast,
          payload: { message: 'system update' }
        ).and_return(broadcast_result)
        described_class.call(message: 'system update', capability: 'transform')
      end

      it 'response contains delivered count' do
        allow(mock_client).to receive(:send_message).and_return(broadcast_result)
        response = described_class.call(message: 'system update')
        data = Legion::JSON.load(response.content.first[:text])
        expect(data[:delivered_count]).to eq(5)
      end

      it 'returns error response on exception' do
        allow(mock_client).to receive(:send_message).and_raise(StandardError, 'broadcast failed')
        response = described_class.call(message: 'system update')
        expect(response.error?).to be true
        data = Legion::JSON.load(response.content.first[:text])
        expect(data[:error]).to include('broadcast failed')
      end
    end
  end
end
