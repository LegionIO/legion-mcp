# frozen_string_literal: true

require 'spec_helper'
require 'legion/mcp'
require_relative '../../support/catalog_stubs'

RSpec.describe 'MCP Server dynamic dispatch' do
  before do
    allow(Legion::Settings).to receive(:dig).and_return(nil)
    Legion::Extensions::Catalog::Registry.reset!
  end

  describe '.dispatch_catalog_tool' do
    it 'dispatches to extension runner when tool is from Catalog' do
      cap = Legion::Extensions::Capability.from_runner(
        extension: 'lex-github', runner: 'PullRequest', function: 'close',
        description: 'Close a PR'
      )
      Legion::Extensions::Catalog::Registry.register(cap)

      runner = double('PullRequest')
      allow(runner).to receive(:close).with(pr_id: 123).and_return({ closed: true })
      stub_const('Legion::Extensions::Github::Runners::PullRequest', runner)

      result = Legion::MCP::Server.dispatch_catalog_tool(
        'legion.github.pull_request.close',
        { pr_id: 123 }
      )
      expect(result[:status]).to eq(:success)
      expect(result[:result]).to eq({ closed: true })
    end

    it 'returns nil for unknown tool names' do
      result = Legion::MCP::Server.dispatch_catalog_tool('unknown.tool', {})
      expect(result).to be_nil
    end
  end
end
