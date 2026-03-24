# frozen_string_literal: true

require 'spec_helper'
require 'legion/mcp'

RSpec.describe Legion::MCP::Tools::MindGrowthHealth do
  let(:mock_client) { double('client') }
  let(:health_data) do
    {
      fitness_scores:          {},
      prune_candidates:        [],
      improvement_candidates:  [],
      evaluated_at:            '2026-03-24T00:00:00Z'
    }
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
        allow(mock_client).to receive(:validate_fitness).and_return(health_data)
        response = described_class.call
        expect(response.error?).to be false
      end

      it 'calls validate_fitness with empty extensions list' do
        expect(mock_client).to receive(:validate_fitness).with(extensions: []).and_return(health_data)
        described_class.call
      end

      it 'response contains health data' do
        allow(mock_client).to receive(:validate_fitness).and_return(health_data)
        response = described_class.call
        data = Legion::JSON.load(response.content.first[:text])
        expect(data[:prune_candidates]).to eq([])
        expect(data[:improvement_candidates]).to eq([])
      end

      it 'returns error response on exception' do
        allow(mock_client).to receive(:validate_fitness).and_raise(StandardError, 'fitness check failed')
        response = described_class.call
        expect(response.error?).to be true
        data = Legion::JSON.load(response.content.first[:text])
        expect(data[:error]).to include('fitness check failed')
      end
    end
  end
end
