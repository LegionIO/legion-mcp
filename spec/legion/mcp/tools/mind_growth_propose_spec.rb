# frozen_string_literal: true

require 'spec_helper'
require 'legion/mcp'

RSpec.describe Legion::MCP::Tools::MindGrowthPropose do
  let(:mock_client) { double('client') }
  let(:proposal_result) do
    { proposal_id: 'prop-abc-123', status: 'pending', category: :cognition }
  end

  describe '.call' do
    context 'when lex-mind-growth is not available' do
      before do
        allow(described_class).to receive(:mind_growth_available?).and_return(false)
      end

      it 'returns an error response' do
        response = described_class.call(category: 'cognition', description: 'A new reasoning module')
        expect(response).to be_a(MCP::Tool::Response)
        expect(response.error?).to be true
      end

      it 'error message mentions lex-mind-growth' do
        response = described_class.call(description: 'A new reasoning module')
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
        allow(mock_client).to receive(:propose_concept).and_return(proposal_result)
        response = described_class.call(category: 'cognition', description: 'A new reasoning module')
        expect(response.error?).to be false
      end

      it 'calls propose_concept with category as symbol' do
        expect(mock_client).to receive(:propose_concept).with(
          category:    :cognition,
          description: 'A new reasoning module',
          name:        nil
        ).and_return(proposal_result)
        described_class.call(category: 'cognition', description: 'A new reasoning module')
      end

      it 'forwards optional name param' do
        expect(mock_client).to receive(:propose_concept).with(
          category:    :memory,
          description: 'Episodic memory buffer',
          name:        'lex-memory-episodic'
        ).and_return(proposal_result)
        described_class.call(category: 'memory', description: 'Episodic memory buffer', name: 'lex-memory-episodic')
      end

      it 'handles nil category gracefully' do
        expect(mock_client).to receive(:propose_concept).with(
          category:    nil,
          description: 'General purpose module',
          name:        nil
        ).and_return(proposal_result)
        described_class.call(description: 'General purpose module')
      end

      it 'response contains proposal data' do
        allow(mock_client).to receive(:propose_concept).and_return(proposal_result)
        response = described_class.call(category: 'cognition', description: 'A new reasoning module')
        data = Legion::JSON.load(response.content.first[:text])
        expect(data[:proposal_id]).to eq('prop-abc-123')
        expect(data[:status]).to eq('pending')
      end

      it 'returns error response on exception' do
        allow(mock_client).to receive(:propose_concept).and_raise(StandardError, 'invalid category')
        response = described_class.call(category: 'unknown', description: 'test')
        expect(response.error?).to be true
        data = Legion::JSON.load(response.content.first[:text])
        expect(data[:error]).to include('invalid category')
      end
    end
  end
end
