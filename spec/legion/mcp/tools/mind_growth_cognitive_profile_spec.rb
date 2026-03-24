# frozen_string_literal: true

require 'spec_helper'
require 'legion/mcp'

RSpec.describe Legion::MCP::Tools::MindGrowthCognitiveProfile do
  let(:mock_client) { double('client') }
  let(:profile_data) do
    {
      coverage:   0.68,
      gaps:       %w[motivation coordination],
      strengths:  %w[cognition memory],
      reference:  'ACT-R',
      categories: { cognition: 0.9, memory: 0.85, motivation: 0.2, coordination: 0.1 }
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
        allow(mock_client).to receive(:cognitive_profile).and_return(profile_data)
        response = described_class.call
        expect(response.error?).to be false
      end

      it 'calls cognitive_profile on the client' do
        expect(mock_client).to receive(:cognitive_profile).and_return(profile_data)
        described_class.call
      end

      it 'response contains profile data' do
        allow(mock_client).to receive(:cognitive_profile).and_return(profile_data)
        response = described_class.call
        data = Legion::JSON.load(response.content.first[:text])
        expect(data[:coverage]).to eq(0.68)
        expect(data[:reference]).to eq('ACT-R')
      end

      it 'returns error response on exception' do
        allow(mock_client).to receive(:cognitive_profile).and_raise(StandardError, 'model unavailable')
        response = described_class.call
        expect(response.error?).to be true
        data = Legion::JSON.load(response.content.first[:text])
        expect(data[:error]).to include('model unavailable')
      end
    end
  end
end
