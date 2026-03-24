# frozen_string_literal: true

require 'spec_helper'
require 'legion/mcp'

RSpec.describe Legion::MCP::Tools::MindGrowthBuildQueue do
  let(:mock_client) { double('client') }
  let(:queue_data) do
    [
      { proposal_id: 'prop-1', name: 'lex-memory-episodic', category: :memory, score: 0.91 },
      { proposal_id: 'prop-2', name: 'lex-attention',       category: :cognition, score: 0.85 }
    ]
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
        allow(mock_client).to receive(:list_proposals).and_return(queue_data)
        response = described_class.call
        expect(response.error?).to be false
      end

      it 'calls list_proposals with status: :approved' do
        expect(mock_client).to receive(:list_proposals).with(status: :approved).and_return(queue_data)
        described_class.call
      end

      it 'response contains queue data' do
        allow(mock_client).to receive(:list_proposals).and_return(queue_data)
        response = described_class.call
        data = Legion::JSON.load(response.content.first[:text])
        expect(data.length).to eq(2)
        expect(data.first[:proposal_id]).to eq('prop-1')
      end

      it 'returns error response on exception' do
        allow(mock_client).to receive(:list_proposals).and_raise(StandardError, 'database error')
        response = described_class.call
        expect(response.error?).to be true
        data = Legion::JSON.load(response.content.first[:text])
        expect(data[:error]).to include('database error')
      end
    end
  end
end
