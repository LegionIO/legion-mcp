# frozen_string_literal: true

require 'spec_helper'
require 'legion/mcp'

RSpec.describe Legion::MCP::Tools::MeshStatus do
  let(:mock_client)  { double('client') }
  let(:status_data) do
    { agents: 4, topology: 'full-mesh', uptime_seconds: 3600, healthy: true }
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
        allow(mock_client).to receive(:mesh_status).and_return(status_data)
        response = described_class.call
        expect(response.error?).to be false
      end

      it 'calls mesh_status on the client' do
        expect(mock_client).to receive(:mesh_status).and_return(status_data)
        described_class.call
      end

      it 'response contains status data' do
        allow(mock_client).to receive(:mesh_status).and_return(status_data)
        response = described_class.call
        data = Legion::JSON.load(response.content.first[:text])
        expect(data[:agents]).to eq(4)
        expect(data[:healthy]).to be true
      end

      it 'returns error response on exception' do
        allow(mock_client).to receive(:mesh_status).and_raise(StandardError, 'mesh offline')
        response = described_class.call
        expect(response.error?).to be true
        data = Legion::JSON.load(response.content.first[:text])
        expect(data[:error]).to include('mesh offline')
      end
    end
  end
end
