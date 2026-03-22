# frozen_string_literal: true

require 'spec_helper'
require 'legion/mcp'

RSpec.describe Legion::MCP::Tools::ListPeers do
  let(:mock_client) { double('client') }
  let(:agents) do
    [
      { id: 'agent-1', capabilities: %w[query transform], status: 'online' },
      { id: 'agent-2', capabilities: ['query'], status: 'online' }
    ]
  end

  describe '.call' do
    context 'when lex-mesh is not available' do
      before do
        allow(described_class).to receive(:mesh_available?).and_return(false)
      end

      it 'returns an error response' do
        response = described_class.call
        expect(response).to be_a(MCP::Tool::Response)
        expect(response.error?).to be true
      end

      it 'error message mentions lex-mesh' do
        response = described_class.call
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
        allow(mock_client).to receive(:find_agents).and_return(agents)
        response = described_class.call
        expect(response.error?).to be false
      end

      it 'calls find_agents with no filter by default' do
        expect(mock_client).to receive(:find_agents).with(capability: nil).and_return(agents)
        described_class.call
      end

      it 'passes capability filter when provided' do
        expect(mock_client).to receive(:find_agents).with(capability: 'query').and_return(agents)
        described_class.call(capability: 'query')
      end

      it 'response contains agent list' do
        allow(mock_client).to receive(:find_agents).and_return(agents)
        response = described_class.call
        data = Legion::JSON.load(response.content.first[:text])
        expect(data).to be_an(Array)
        expect(data.first[:id]).to eq('agent-1')
      end

      it 'returns error response on exception' do
        allow(mock_client).to receive(:find_agents).and_raise(StandardError, 'mesh unreachable')
        response = described_class.call
        expect(response.error?).to be true
        data = Legion::JSON.load(response.content.first[:text])
        expect(data[:error]).to include('mesh unreachable')
      end
    end
  end
end
