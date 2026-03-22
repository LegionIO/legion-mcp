# frozen_string_literal: true

require 'spec_helper'
require 'legion/mcp'

RSpec.describe Legion::MCP::Tools::NotifyPeer do
  let(:mock_client)   { double('client') }
  let(:send_result)   { { delivered: true, message_id: 'msg-42' } }

  describe '.call' do
    context 'when lex-mesh is not available' do
      before do
        allow(described_class).to receive(:mesh_available?).and_return(false)
      end

      it 'returns an error response' do
        response = described_class.call(to: 'agent-1', message: 'hello')
        expect(response).to be_a(MCP::Tool::Response)
        expect(response.error?).to be true
      end

      it 'error message mentions lex-mesh' do
        response = described_class.call(to: 'agent-1', message: 'hello')
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
        allow(mock_client).to receive(:send_message).and_return(send_result)
        response = described_class.call(to: 'agent-1', message: 'hello')
        expect(response.error?).to be false
      end

      it 'calls send_message with unicast pattern' do
        expect(mock_client).to receive(:send_message).with(
          from:    'legion.mcp',
          to:      'agent-1',
          pattern: :unicast,
          payload: { message: 'hello' }
        ).and_return(send_result)
        described_class.call(to: 'agent-1', message: 'hello')
      end

      it 'response contains delivery result' do
        allow(mock_client).to receive(:send_message).and_return(send_result)
        response = described_class.call(to: 'agent-1', message: 'hello')
        data = Legion::JSON.load(response.content.first[:text])
        expect(data[:delivered]).to be true
      end

      it 'returns error response on exception' do
        allow(mock_client).to receive(:send_message).and_raise(StandardError, 'agent offline')
        response = described_class.call(to: 'agent-1', message: 'hello')
        expect(response.error?).to be true
        data = Legion::JSON.load(response.content.first[:text])
        expect(data[:error]).to include('agent offline')
      end
    end
  end
end
