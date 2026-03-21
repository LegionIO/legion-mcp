# frozen_string_literal: true

require 'spec_helper'
require 'legion/mcp'

RSpec.describe Legion::MCP::Tools::EvalRun do
  let(:eval_result) do
    {
      evaluator: 'relevance',
      results:   [{ row_index: 0, passed: true, score: 0.9 }],
      summary:   { total: 1, passed: 1, failed: 0, avg_score: 0.9 }
    }
  end

  describe '.call' do
    context 'when lex-eval is not loaded' do
      before do
        allow(described_class).to receive(:extension_loaded?).with('eval').and_return(false)
      end

      it 'returns an error response' do
        response = described_class.call(evaluator_name: 'relevance', input: 'q', output: 'a')
        expect(response.error?).to be true
      end

      it 'error message mentions lex-eval' do
        response = described_class.call(evaluator_name: 'relevance', input: 'q', output: 'a')
        data = Legion::JSON.load(response.content.first[:text])
        expect(data[:error]).to include('lex-eval')
      end
    end

    context 'when lex-eval is loaded' do
      let(:mock_client) { double('client') }

      before do
        allow(described_class).to receive(:extension_loaded?).with('eval').and_return(true)
        stub_const('Legion::Extensions::Eval::Client', Class.new)
        allow(Legion::Extensions::Eval::Client).to receive(:new).and_return(mock_client)
        allow(described_class).to receive(:require).with('legion/extensions/eval/client')
        allow(described_class).to receive(:db).and_return(nil)
      end

      it 'returns a successful response' do
        allow(mock_client).to receive(:run_evaluation).and_return(eval_result)
        response = described_class.call(evaluator_name: 'relevance', input: 'What is AI?', output: 'Artificial intelligence.')
        expect(response.error?).to be false
      end

      it 'passes evaluator_name and a single-item inputs array' do
        expect(mock_client).to receive(:run_evaluation).with(
          evaluator_name: 'relevance',
          inputs:         [{ input: 'What is AI?', output: 'Artificial intelligence.' }]
        ).and_return(eval_result)
        described_class.call(evaluator_name: 'relevance', input: 'What is AI?', output: 'Artificial intelligence.')
      end

      it 'includes expected in inputs when provided' do
        expect(mock_client).to receive(:run_evaluation).with(
          evaluator_name: 'relevance',
          inputs:         [{ input: 'q', output: 'a', expected: 'expected answer' }]
        ).and_return(eval_result)
        described_class.call(evaluator_name: 'relevance', input: 'q', output: 'a', expected: 'expected answer')
      end

      it 'omits expected from inputs when not provided' do
        expect(mock_client).to receive(:run_evaluation).with(
          evaluator_name: 'relevance',
          inputs:         [{ input: 'q', output: 'a' }]
        ).and_return(eval_result)
        described_class.call(evaluator_name: 'relevance', input: 'q', output: 'a')
      end

      it 'response contains evaluation results' do
        allow(mock_client).to receive(:run_evaluation).and_return(eval_result)
        response = described_class.call(evaluator_name: 'relevance', input: 'q', output: 'a')
        data = Legion::JSON.load(response.content.first[:text])
        expect(data[:evaluator]).to eq('relevance')
        expect(data[:summary][:passed]).to eq(1)
      end
    end
  end
end
