# frozen_string_literal: true

require 'spec_helper'
require 'legion/mcp'

RSpec.describe Legion::MCP::Tools::ToolAudit do
  before do
    allow(Legion::Settings).to receive(:dig).and_return(nil)
  end

  describe '.call' do
    context 'with default mode (summary)' do
      it 'returns a summary response' do
        response = described_class.call
        expect(response).to be_a(MCP::Tool::Response)
        expect(response.error?).to be false
        data = Legion::JSON.load(response.content.first[:text])
        expect(data).to have_key(:total_tools)
        expect(data).to have_key(:by_category)
      end
    end

    context 'with mode: matrix' do
      it 'returns capability matrix' do
        response = described_class.call(mode: 'matrix')
        expect(response.error?).to be false
        data = Legion::JSON.load(response.content.first[:text])
        expect(data).to be_an(Array)
        expect(data.first).to have_key(:name)
        expect(data.first).to have_key(:reads)
        expect(data.first).to have_key(:writes)
      end
    end

    context 'with mode: issues' do
      it 'returns only tools with quality warnings' do
        response = described_class.call(mode: 'issues')
        expect(response.error?).to be false
        data = Legion::JSON.load(response.content.first[:text])
        expect(data).to be_an(Array)
        data.each { |entry| expect(entry[:quality].to_s).to eq('warn') }
      end
    end

    context 'when an error occurs' do
      before do
        allow(Legion::MCP::ToolQuality).to receive(:summary).and_raise(StandardError, 'audit error')
      end

      it 'returns error response' do
        response = described_class.call
        expect(response.error?).to be true
        data = Legion::JSON.load(response.content.first[:text])
        expect(data[:error]).to include('audit error')
      end
    end
  end
end
