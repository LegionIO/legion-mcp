# frozen_string_literal: true

require 'spec_helper'
require 'legion/mcp'

RSpec.describe Legion::MCP::Tools::DatasetList do
  let(:datasets) do
    [
      { name: 'qa-pairs', description: 'QA test set', latest_version: 3, row_count: 100 },
      { name: 'golden-set', description: nil, latest_version: 1, row_count: 50 }
    ]
  end

  describe '.call' do
    context 'when lex-dataset is not loaded' do
      before do
        allow(described_class).to receive(:extension_loaded?).with('dataset').and_return(false)
      end

      it 'returns an error response' do
        response = described_class.call
        expect(response).to be_a(MCP::Tool::Response)
        expect(response.error?).to be true
      end

      it 'error message mentions lex-dataset' do
        response = described_class.call
        data = Legion::JSON.load(response.content.first[:text])
        expect(data[:error]).to include('lex-dataset')
      end
    end

    context 'when lex-dataset is loaded' do
      let(:mock_client) { double('client', list_datasets: datasets) }

      before do
        allow(described_class).to receive(:extension_loaded?).with('dataset').and_return(true)
        stub_const('Legion::Extensions::Dataset::Client', Class.new)
        allow(Legion::Extensions::Dataset::Client).to receive(:new).and_return(mock_client)
        allow(described_class).to receive(:require).with('legion/extensions/dataset/client')
        allow(described_class).to receive(:db).and_return(nil)
      end

      it 'returns a successful response' do
        response = described_class.call
        expect(response.error?).to be false
      end

      it 'calls list_datasets on the client' do
        expect(mock_client).to receive(:list_datasets)
        described_class.call
      end

      it 'response contains dataset data' do
        response = described_class.call
        data = Legion::JSON.load(response.content.first[:text])
        expect(data).to be_an(Array)
        expect(data.first[:name]).to eq('qa-pairs')
      end
    end
  end
end
