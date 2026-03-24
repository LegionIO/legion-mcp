# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Legion::MCP::Client::Pool do
  before { described_class.reset! }

  describe '.connection_for' do
    it 'creates and caches connections' do
      Legion::MCP::Client::ServerRegistry.reset!
      Legion::MCP::Client::ServerRegistry.register(
        'test', transport: :http, url: 'http://localhost/mcp'
      )

      conn = described_class.connection_for('test')
      expect(conn).to be_a(Legion::MCP::Client::Connection)
      expect(described_class.connection_for('test')).to equal(conn) # same object
    end

    it 'returns nil for unknown server' do
      Legion::MCP::Client::ServerRegistry.reset!
      expect(described_class.connection_for('nonexistent')).to be_nil
    end
  end

  describe '.all_tools' do
    it 'aggregates tools from all healthy connections' do
      Legion::MCP::Client::ServerRegistry.reset!
      Legion::MCP::Client::ServerRegistry.register(
        'server_a', transport: :http, url: 'http://a.com/mcp'
      )

      conn = double('Connection', tools: [{ name: 'tool_a' }], name: 'server_a')
      allow(described_class).to receive(:connection_for).with('server_a').and_return(conn)

      tools = described_class.all_tools
      expect(tools.size).to eq(1)
      expect(tools.first[:name]).to eq('tool_a')
    end
  end
end
