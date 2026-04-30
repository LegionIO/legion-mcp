# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Client connection tracing context' do
  let(:logger) { spy('logger') }
  let(:mock_transport) { instance_double(MCP::Client::Stdio, close: nil) }
  let(:mock_client) { instance_double(MCP::Client) }
  let(:trace_context) do
    {
      conversation_id: 'mcp_test-conv-123',
      request_id:      'req_42',
      trace_id:        'a' * 32
    }
  end

  before do
    allow_any_instance_of(Legion::MCP::Client::Connection).to receive(:log).and_return(logger)
    allow(MCP::Client::Stdio).to receive(:new).and_return(mock_transport)
    allow(MCP::Client).to receive(:new).and_return(mock_client)
    allow(mock_client).to receive(:tools).and_return([])
    allow(mock_client).to receive(:call_tool).and_return(
      { 'result' => { 'content' => [{ 'type' => 'text', 'text' => 'ok' }], 'isError' => false } }
    )
  end

  describe '#call_tool with context' do
    it 'logs exchange_id on start' do
      conn = Legion::MCP::Client::Connection.new(name: 'test', transport: :stdio, command: 'echo')
      conn.connect

      conn.call_tool(name: 'some_tool', arguments: {}, context: trace_context)

      expect(logger).to have_received(:info).with(
        include('client.tool_call.start', 'exchange_id=')
      ).at_least(:once)
    end

    it 'generates unique exchange_ids across calls' do
      conn = Legion::MCP::Client::Connection.new(name: 'test', transport: :stdio, command: 'echo')
      conn.connect

      logged_lines = []
      allow(logger).to receive(:info) { |msg| logged_lines << msg }

      2.times { conn.call_tool(name: 'some_tool', arguments: {}, context: trace_context) }

      start_lines = logged_lines.select { |l| l.include?('client.tool_call.start') }
      exchange_ids = start_lines.filter_map { |l| l[/exchange_id="(exch_[0-9a-f]+)"/, 1] }

      expect(exchange_ids.uniq.size).to eq(2)
    end

    it 'logs trace_id from context' do
      conn = Legion::MCP::Client::Connection.new(name: 'test', transport: :stdio, command: 'echo')
      conn.connect

      conn.call_tool(name: 'some_tool', arguments: {}, context: trace_context)

      expect(logger).to have_received(:info).with(
        include('trace_id=', 'a' * 32)
      ).at_least(:once)
    end

    it 'logs duration_ms on completion' do
      conn = Legion::MCP::Client::Connection.new(name: 'test', transport: :stdio, command: 'echo')
      conn.connect

      conn.call_tool(name: 'some_tool', arguments: {}, context: trace_context)

      expect(logger).to have_received(:info).with(include('client.tool_call.complete', 'duration_ms='))
    end

    it 'works without context (backward compatible)' do
      conn = Legion::MCP::Client::Connection.new(name: 'test', transport: :stdio, command: 'echo')
      conn.connect

      result = conn.call_tool(name: 'some_tool', arguments: {})

      expect(result[:error]).to be(false)
    end
  end

  describe 'HTTP trace header injection' do
    let(:mock_http_transport) { instance_double(MCP::Client::HTTP) }

    before do
      allow(MCP::Client::HTTP).to receive(:new).and_return(mock_http_transport)
      allow(MCP::Client).to receive(:new).and_return(mock_client)
      allow(mock_http_transport).to receive(:instance_variable_defined?).with(:@headers).and_return(true)
      allow(mock_http_transport).to receive(:instance_variable_set)
      allow(mock_http_transport).to receive(:instance_variable_get).with(:@headers).and_return({})
    end

    it 'injects trace headers for HTTP transport' do
      conn = Legion::MCP::Client::Connection.new(
        name: 'test-http', transport: :http, url: 'http://localhost:8080/mcp'
      )
      conn.connect

      conn.call_tool(name: 'some_tool', arguments: {}, context: trace_context)

      expect(mock_http_transport).to have_received(:instance_variable_set).with(
        :@headers,
        hash_including(
          'x-legion-trace-id' => trace_context[:trace_id],
          'x-legion-conversation-id' => trace_context[:conversation_id]
        )
      )
    end

    it 'includes W3C traceparent header' do
      conn = Legion::MCP::Client::Connection.new(
        name: 'test-http', transport: :http, url: 'http://localhost:8080/mcp'
      )
      conn.connect

      conn.call_tool(name: 'some_tool', arguments: {}, context: trace_context)

      expect(mock_http_transport).to have_received(:instance_variable_set).with(
        :@headers,
        hash_including('traceparent' => match(/\A00-#{'a' * 32}-[0-9a-f]{16}-01\z/))
      )
    end

    it 'skips header injection for stdio transport' do
      conn = Legion::MCP::Client::Connection.new(
        name: 'test-stdio', transport: :stdio, command: 'echo'
      )
      conn.connect

      # Should not raise when calling with context on stdio transport
      result = conn.call_tool(name: 'some_tool', arguments: {}, context: trace_context)
      expect(result[:error]).to be(false)
    end

    it 'skips header injection when context is empty' do
      conn = Legion::MCP::Client::Connection.new(
        name: 'test-http', transport: :http, url: 'http://localhost:8080/mcp'
      )
      conn.connect

      conn.call_tool(name: 'some_tool', arguments: {}, context: {})

      # instance_variable_set should only be called during connect_http for @base_headers setup,
      # not for trace header injection
    end
  end
end
