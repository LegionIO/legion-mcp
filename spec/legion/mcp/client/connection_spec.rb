# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Legion::MCP::Client::Connection do
  before do
    allow(Legion::Logging).to receive(:info)
    allow(Legion::Logging).to receive(:warn)
  end

  describe '#initialize' do
    it 'creates a stdio connection' do
      conn = described_class.new(
        name: 'test-server',
        transport: :stdio,
        command: 'echo hello'
      )
      expect(conn.name).to eq('test-server')
      expect(conn.transport_type).to eq(:stdio)
      expect(conn.connected?).to eq(false)
    end

    it 'creates an HTTP connection' do
      conn = described_class.new(
        name: 'test-http',
        transport: :http,
        url: 'http://localhost:8080/mcp'
      )
      expect(conn.name).to eq('test-http')
      expect(conn.transport_type).to eq(:http)
    end
  end

  describe '#tools' do
    it 'returns cached tools list' do
      conn = described_class.new(name: 'test', transport: :stdio, command: 'echo')
      allow(conn).to receive(:fetch_tools).and_return([
        { name: 'list_files', description: 'List files', input_schema: {} }
      ])
      tools = conn.tools
      expect(tools.size).to eq(1)
      expect(tools.first[:name]).to eq('list_files')
    end

    it 'caches tools with TTL' do
      conn = described_class.new(name: 'test', transport: :stdio, command: 'echo')
      allow(conn).to receive(:fetch_tools).and_return([{ name: 'a' }])
      conn.tools
      conn.tools # second call should use cache
      expect(conn).to have_received(:fetch_tools).once
    end
  end

  describe '#call_tool' do
    it 'executes a tool and returns result' do
      conn = described_class.new(name: 'test', transport: :stdio, command: 'echo')
      allow(conn).to receive(:execute_tool_call).and_return({
        content: [{ type: 'text', text: '["file1.rb", "file2.rb"]' }]
      })

      result = conn.call_tool(name: 'list_files', arguments: { path: '.' })
      expect(result).to be_a(Hash)
      expect(result[:content]).not_to be_empty
    end

    it 'logs tool call start and completion' do
      conn = described_class.new(name: 'test', transport: :stdio, command: 'echo')
      allow(conn).to receive(:execute_tool_call).and_return({
        content: [{ type: 'text', text: '["file1.rb"]' }]
      })

      conn.call_tool(name: 'list_files', arguments: { path: '.' })

      expect(Legion::Logging).to have_received(:info).with(include('[mcp] client.tool_call.start', 'tool_name="list_files"'))
      expect(Legion::Logging).to have_received(:info).with(include('[mcp] client.tool_call.complete', 'tool_name="list_files"'))
    end
  end
end
