# frozen_string_literal: true

require 'spec_helper'
require 'legion/mcp'

RSpec.describe Legion::MCP::Tools::StructuralIndexTool do
  before do
    allow(Legion::Settings).to receive(:dig).and_return(nil)
  end

  describe '.call' do
    let(:index) do
      {
        extensions: [],
        tools: [{ name: 'legion.do', description: 'Do action', catalog: false }],
        generated_at: '2026-03-31T00:00:00Z'
      }
    end

    before do
      allow(Legion::MCP::StructuralIndex).to receive(:load_or_build).and_return(index)
      allow(Legion::MCP::StructuralIndex).to receive(:build).and_return(index)
      allow(Legion::MCP::StructuralIndex).to receive(:save_cache).and_return(index)
      allow(Legion::MCP::StructuralIndex).to receive(:filter).and_call_original
    end

    context 'with no arguments' do
      it 'returns the full structural index' do
        response = described_class.call
        expect(response).to be_a(MCP::Tool::Response)
        expect(response.error?).to be false
        data = Legion::JSON.load(response.content.first[:text])
        expect(data).to have_key(:tools)
        expect(data).to have_key(:extensions)
      end
    end

    context 'with type filter' do
      it 'returns only tools when type is tools' do
        response = described_class.call(type: 'tools')
        expect(response.error?).to be false
        data = Legion::JSON.load(response.content.first[:text])
        expect(data).to have_key(:tools)
        expect(data).not_to have_key(:extensions)
      end
    end

    context 'with refresh: true' do
      it 'forces rebuild of the index' do
        expect(Legion::MCP::StructuralIndex).to receive(:build).and_return(index)
        expect(Legion::MCP::StructuralIndex).to receive(:save_cache).with(index).and_return(index)
        described_class.call(refresh: true)
      end
    end

    context 'with extension filter' do
      it 'filters by extension name' do
        expect(Legion::MCP::StructuralIndex).to receive(:filter).with(index, extension: 'http', type: nil)
        described_class.call(extension: 'http')
      end
    end

    context 'when an error occurs' do
      before do
        allow(Legion::MCP::StructuralIndex).to receive(:load_or_build).and_raise(StandardError, 'index error')
      end

      it 'returns an error response' do
        response = described_class.call
        expect(response.error?).to be true
        data = Legion::JSON.load(response.content.first[:text])
        expect(data[:error]).to include('index error')
      end
    end
  end
end
