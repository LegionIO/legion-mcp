# frozen_string_literal: true

require 'spec_helper'
require 'legion/mcp'

RSpec.describe Legion::MCP::OverrideBroadcast do
  let(:confidence_stub) do
    overrides = {}
    mutex = Mutex.new
    Module.new do
      define_method(:record) do |tool:, lex:, confidence:|
        mutex.synchronize do
          overrides[tool] = {
            tool: tool, lex: lex, confidence: confidence.clamp(0.0, 1.0),
            hit_count: 0, miss_count: 0
          }
        end
      end

      define_method(:lookup) do |tool|
        mutex.synchronize { overrides[tool]&.dup }
      end

      define_method(:reset!) do
        mutex.synchronize { overrides.clear }
      end

      %i[record lookup reset!].each { |m| module_function m }
    end
  end

  before do
    stub_const('Legion::LLM::OverrideConfidence', confidence_stub)
    confidence_stub.reset!
  end

  describe '.publish_confirmation' do
    it 'publishes override confirmation when Transport is available' do
      msg = double('Dynamic', publish: true)
      stub_const('Legion::Transport::Messages::Dynamic', Class.new)
      allow(Legion::Transport::Messages::Dynamic).to receive(:new).and_return(msg)
      allow(Legion::Settings).to receive(:dig).and_return('test_node')

      expect(msg).to receive(:publish)
      described_class.publish_confirmation(
        tool: 'close_pr', lex: 'lex-github:PullRequest:close',
        confidence: 0.85, tests: 3
      )
    end

    it 'does not crash when Transport is not available' do
      expect {
        described_class.publish_confirmation(
          tool: 'close_pr', lex: 'lex-github:PullRequest:close',
          confidence: 0.85, tests: 3
        )
      }.not_to raise_error
    end
  end

  describe '#store_to_apollo' do
    context 'when Legion::Apollo is available' do
      before do
        stub_const('Legion::Apollo', double(started?: true, ingest: { success: true }))
      end

      it 'calls Legion::Apollo.ingest' do
        described_class.send(:store_to_apollo, tool: 't', lex: 'l', confidence: 0.9, tests: 3, node: 'n1')
        expect(Legion::Apollo).to have_received(:ingest)
      end
    end

    context 'when Legion::Apollo is not available' do
      it 'does not raise' do
        expect do
          described_class.send(:store_to_apollo, tool: 't', lex: 'l', confidence: 0.9, tests: 3, node: 'n1')
        end.not_to raise_error
      end
    end
  end

  describe '.receive_confirmation' do
    it 'boosts local confidence from remote confirmation' do
      confidence_stub.record(
        tool: 'close_pr', lex: 'lex-github:PullRequest:close', confidence: 0.5
      )

      described_class.receive_confirmation(
        tool: 'close_pr', lex: 'lex-github:PullRequest:close',
        confidence: 0.85, tests: 5, node: 'node_a'
      )

      entry = confidence_stub.lookup('close_pr')
      expect(entry[:confidence]).to be > 0.5
    end

    it 'seeds confidence when no local override exists' do
      described_class.receive_confirmation(
        tool: 'close_pr', lex: 'lex-github:PullRequest:close',
        confidence: 0.85, tests: 5, node: 'node_a'
      )

      entry = confidence_stub.lookup('close_pr')
      expect(entry).not_to be_nil
      expect(entry[:confidence]).to be > 0
      expect(entry[:confidence]).to be <= 0.85
    end
  end
end
