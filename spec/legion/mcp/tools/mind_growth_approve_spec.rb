# frozen_string_literal: true

require 'spec_helper'
require 'legion/mcp'

RSpec.describe Legion::MCP::Tools::MindGrowthApprove do
  let(:mock_client) { double('client') }
  let(:eval_result) do
    { proposal_id: 'prop-abc-123', score: 0.87, approved: true, rationale: 'High utility' }
  end

  describe '.call' do
    context 'when lex-mind-growth is not available' do
      before do
        allow(described_class).to receive(:mind_growth_available?).and_return(false)
      end

      it 'returns an error response' do
        response = described_class.call(proposal_id: 'prop-abc-123')
        expect(response).to be_a(MCP::Tool::Response)
        expect(response.error?).to be true
      end

      it 'error message mentions lex-mind-growth' do
        response = described_class.call(proposal_id: 'prop-abc-123')
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
        allow(mock_client).to receive(:evaluate_proposal).and_return(eval_result)
        response = described_class.call(proposal_id: 'prop-abc-123')
        expect(response.error?).to be false
      end

      it 'calls evaluate_proposal with the proposal_id' do
        expect(mock_client).to receive(:evaluate_proposal).with(
          proposal_id: 'prop-abc-123'
        ).and_return(eval_result)
        described_class.call(proposal_id: 'prop-abc-123')
      end

      it 'response contains evaluation data' do
        allow(mock_client).to receive(:evaluate_proposal).and_return(eval_result)
        response = described_class.call(proposal_id: 'prop-abc-123')
        data = Legion::JSON.load(response.content.first[:text])
        expect(data[:score]).to eq(0.87)
        expect(data[:approved]).to be true
      end

      it 'returns error response on exception' do
        allow(mock_client).to receive(:evaluate_proposal).and_raise(StandardError, 'proposal not found')
        response = described_class.call(proposal_id: 'missing-id')
        expect(response.error?).to be true
        data = Legion::JSON.load(response.content.first[:text])
        expect(data[:error]).to include('proposal not found')
      end
    end
  end
end
