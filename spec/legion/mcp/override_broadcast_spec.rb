# frozen_string_literal: true

require 'spec_helper'
require 'legion/mcp'

# Stub OverrideConfidence for broadcast tests
module Legion
  module LLM
    module OverrideConfidence
      @overrides = {}
      @mutex = Mutex.new

      module_function

      def record(tool:, lex:, confidence:)
        @mutex.synchronize do
          @overrides[tool] = {
            tool: tool, lex: lex, confidence: confidence.clamp(0.0, 1.0),
            hit_count: 0, miss_count: 0
          }
        end
      end

      def lookup(tool)
        @mutex.synchronize { @overrides[tool]&.dup }
      end

      def reset!
        @mutex.synchronize { @overrides.clear }
      end
    end
  end
end

RSpec.describe Legion::MCP::OverrideBroadcast do
  before { Legion::LLM::OverrideConfidence.reset! }

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

  describe '.receive_confirmation' do
    it 'boosts local confidence from remote confirmation' do
      Legion::LLM::OverrideConfidence.record(
        tool: 'close_pr', lex: 'lex-github:PullRequest:close', confidence: 0.5
      )

      described_class.receive_confirmation(
        tool: 'close_pr', lex: 'lex-github:PullRequest:close',
        confidence: 0.85, tests: 5, node: 'node_a'
      )

      entry = Legion::LLM::OverrideConfidence.lookup('close_pr')
      expect(entry[:confidence]).to be > 0.5
    end

    it 'seeds confidence when no local override exists' do
      described_class.receive_confirmation(
        tool: 'close_pr', lex: 'lex-github:PullRequest:close',
        confidence: 0.85, tests: 5, node: 'node_a'
      )

      entry = Legion::LLM::OverrideConfidence.lookup('close_pr')
      expect(entry).not_to be_nil
      expect(entry[:confidence]).to be > 0
      expect(entry[:confidence]).to be <= 0.85
    end
  end
end
