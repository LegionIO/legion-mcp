# frozen_string_literal: true

require 'spec_helper'
require 'legion/mcp'

RSpec.describe Legion::MCP::Tools::ExperimentResults do
  describe '.call' do
    context 'when lex-dataset is not loaded' do
      before do
        allow(described_class).to receive(:extension_loaded?).with('dataset').and_return(false)
      end

      it 'returns an error response' do
        response = described_class.call(name: 'exp-1')
        expect(response.error?).to be true
      end

      it 'error message mentions lex-dataset' do
        response = described_class.call(name: 'exp-1')
        data = Legion::JSON.load(response.content.first[:text])
        expect(data[:error]).to include('lex-dataset')
      end
    end

    context 'when lex-dataset is loaded' do
      let(:mock_db) { double('db') }
      let(:mock_client) { double('client') }

      before do
        allow(described_class).to receive(:extension_loaded?).with('dataset').and_return(true)
        stub_const('Legion::Extensions::Dataset::Client', Class.new)
        allow(Legion::Extensions::Dataset::Client).to receive(:new).and_return(mock_client)
        allow(described_class).to receive(:require).with('legion/extensions/dataset/client')
        allow(described_class).to receive(:db).and_return(nil)
        allow(mock_client).to receive(:instance_variable_get).with(:@db).and_return(mock_db)
      end

      it 'returns not_found when experiment does not exist' do
        allow(mock_db).to receive(:[]).with(:experiments).and_return(
          double('dataset', where: double('chain', first: nil))
        )
        response = described_class.call(name: 'missing-exp')
        data = Legion::JSON.load(response.content.first[:text])
        expect(data[:error]).to eq('not_found')
      end

      it 'returns experiment data when found' do
        exp_row = { id: 1, name: 'exp-1', status: 'completed', created_at: nil,
                    completed_at: nil, summary: '{"total":2,"passed":2}' }
        result_rows = [{ row_index: 0, passed: true, latency_ms: 100 }]

        experiments_ds = double('experiments_ds')
        allow(experiments_ds).to receive(:where).with(name: 'exp-1').and_return(
          double('chain', first: exp_row)
        )

        results_ds = double('results_ds')
        allow(results_ds).to receive(:where).with(experiment_id: 1).and_return(
          double('chain', order: double('ordered', all: result_rows))
        )

        allow(mock_db).to receive(:[]).with(:experiments).and_return(experiments_ds)
        allow(mock_db).to receive(:[]).with(:experiment_results).and_return(results_ds)

        response = described_class.call(name: 'exp-1')
        expect(response.error?).to be false
        data = Legion::JSON.load(response.content.first[:text])
        expect(data[:name]).to eq('exp-1')
        expect(data[:status]).to eq('completed')
        expect(data[:rows]).to be_an(Array)
      end
    end
  end
end
