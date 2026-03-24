# frozen_string_literal: true

require 'spec_helper'
require 'legion/mcp'

RSpec.describe Legion::MCP::Tools::MindGrowthStatus do
  let(:mock_client) { double('client') }
  let(:status_data) do
    { proposals: 3, approved: 1, cognitive_coverage: 0.72, categories: %w[cognition memory] }
  end

  describe '.call' do
    context 'when lex-mind-growth is not available' do
      before do
        allow(described_class).to receive(:mind_growth_available?).and_return(false)
      end

      it 'returns an error response' do
        response = described_class.call
        expect(response).to be_a(MCP::Tool::Response)
        expect(response.error?).to be true
      end

      it 'error message mentions lex-mind-growth' do
        response = described_class.call
        data = Legion::JSON.load(response.content.first[:text])
        expect(data[:error]).to include('lex-mind-growth')
      end
    end

    context 'when lex-mind-growth is available' do
      before do
        allow(described_class).to receive(:mind_growth_available?).and_return(true)
        allow(described_class).to receive(:mind_growth_client).and_return(mock_client)
      end

      it 'returns a successful response' do
        allow(mock_client).to receive(:growth_status).and_return(status_data)
        response = described_class.call
        expect(response.error?).to be false
      end

      it 'calls growth_status on the client' do
        expect(mock_client).to receive(:growth_status).and_return(status_data)
        described_class.call
      end

      it 'response contains status data' do
        allow(mock_client).to receive(:growth_status).and_return(status_data)
        response = described_class.call
        data = Legion::JSON.load(response.content.first[:text])
        expect(data[:proposals]).to eq(3)
        expect(data[:approved]).to eq(1)
      end

      it 'returns error response on exception' do
        allow(mock_client).to receive(:growth_status).and_raise(StandardError, 'service unavailable')
        response = described_class.call
        expect(response.error?).to be true
        data = Legion::JSON.load(response.content.first[:text])
        expect(data[:error]).to include('service unavailable')
      end
    end
  end
end
