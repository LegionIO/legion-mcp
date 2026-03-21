# frozen_string_literal: true

require 'spec_helper'
require 'legion/mcp'

RSpec.describe Legion::MCP::Tools::DatasetShow do
  let(:dataset_data) do
    { name: 'qa-pairs', version: 2, version_id: 5, row_count: 3,
      rows: [{ row_index: 0, input: 'q1', expected_output: 'a1' }] }
  end

  describe '.call' do
    context 'when lex-dataset is not loaded' do
      before do
        allow(described_class).to receive(:extension_loaded?).with('dataset').and_return(false)
      end

      it 'returns an error response' do
        response = described_class.call(name: 'qa-pairs')
        expect(response.error?).to be true
      end

      it 'error message mentions lex-dataset' do
        response = described_class.call(name: 'qa-pairs')
        data = Legion::JSON.load(response.content.first[:text])
        expect(data[:error]).to include('lex-dataset')
      end
    end

    context 'when lex-dataset is loaded' do
      let(:mock_client) { double('client') }

      before do
        allow(described_class).to receive(:extension_loaded?).with('dataset').and_return(true)
        stub_const('Legion::Extensions::Dataset::Client', Class.new)
        allow(Legion::Extensions::Dataset::Client).to receive(:new).and_return(mock_client)
        allow(described_class).to receive(:require).with('legion/extensions/dataset/client')
        allow(described_class).to receive(:db).and_return(nil)
      end

      it 'returns a successful response' do
        allow(mock_client).to receive(:get_dataset).and_return(dataset_data)
        response = described_class.call(name: 'qa-pairs')
        expect(response.error?).to be false
      end

      it 'passes name to get_dataset' do
        expect(mock_client).to receive(:get_dataset).with(name: 'qa-pairs', version: nil).and_return(dataset_data)
        described_class.call(name: 'qa-pairs')
      end

      it 'passes version when provided' do
        expect(mock_client).to receive(:get_dataset).with(name: 'qa-pairs', version: 2).and_return(dataset_data)
        described_class.call(name: 'qa-pairs', version: 2)
      end

      it 'response contains dataset rows' do
        allow(mock_client).to receive(:get_dataset).and_return(dataset_data)
        response = described_class.call(name: 'qa-pairs')
        data = Legion::JSON.load(response.content.first[:text])
        expect(data[:name]).to eq('qa-pairs')
        expect(data[:rows]).to be_an(Array)
      end
    end
  end
end
