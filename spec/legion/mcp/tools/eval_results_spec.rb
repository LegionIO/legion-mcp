# frozen_string_literal: true

require 'spec_helper'
require 'legion/mcp'

RSpec.describe Legion::MCP::Tools::EvalResults do
  describe '.call' do
    context 'when lex-dataset is not loaded' do
      before do
        allow(described_class).to receive(:extension_loaded?).with('dataset').and_return(false)
      end

      it 'returns an error response' do
        response = described_class.call(experiment_name: 'run-1')
        expect(response.error?).to be true
      end

      it 'error message mentions lex-dataset' do
        response = described_class.call(experiment_name: 'run-1')
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
        response = described_class.call(experiment_name: 'missing')
        data = Legion::JSON.load(response.content.first[:text])
        expect(data[:error]).to eq('not_found')
      end

      it 'returns experiment results when found' do
        exp_row = { id: 2, name: 'run-1', status: 'completed', created_at: nil,
                    completed_at: nil, summary: '{"total":1,"passed":1}' }
        result_rows = [{ row_index: 0, passed: true, latency_ms: 80 }]

        experiments_ds = double('experiments_ds')
        allow(experiments_ds).to receive(:where).with(name: 'run-1').and_return(
          double('chain', first: exp_row)
        )

        results_ds = double('results_ds')
        allow(results_ds).to receive(:where).with(experiment_id: 2).and_return(
          double('chain', order: double('ordered', all: result_rows))
        )

        allow(mock_db).to receive(:[]).with(:experiments).and_return(experiments_ds)
        allow(mock_db).to receive(:[]).with(:experiment_results).and_return(results_ds)

        response = described_class.call(experiment_name: 'run-1')
        expect(response.error?).to be false
        data = Legion::JSON.load(response.content.first[:text])
        expect(data[:name]).to eq('run-1')
        expect(data[:rows].first[:passed]).to be true
      end
    end
  end
end
