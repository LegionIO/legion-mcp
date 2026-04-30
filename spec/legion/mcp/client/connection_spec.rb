# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Legion::MCP::Client::Connection do
  let(:logger) { spy('logger') }

  before do
    allow_any_instance_of(described_class).to receive(:log).and_return(logger)
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
      expect(conn.connected?).to be(false)
    end

    it 'creates an HTTP connection' do
      conn = described_class.new(
        name: 'test-http',
        transport: :http,
        url: 'http://localhost:8080/mcp'
      )
      expect(conn.name).to eq('test-http')
      expect(conn.transport_type).to eq(:http)
      expect(conn.connected?).to be(false)
    end
  end

  describe '#connected?' do
    it 'returns false before connect is called' do
      conn = described_class.new(name: 'test', transport: :stdio, command: 'echo')
      expect(conn.connected?).to be(false)
    end
  end

  describe '#connect' do
    it 'raises ArgumentError for unknown transport type' do
      conn = described_class.new(name: 'test', transport: :unknown)
      expect { conn.connect }.to raise_error(ArgumentError, /Unknown transport/)
    end

    it 'raises ArgumentError when stdio transport lacks command' do
      conn = described_class.new(name: 'test', transport: :stdio)
      expect { conn.connect }.to raise_error(ArgumentError, /command/)
    end

    it 'raises ArgumentError when http transport lacks url' do
      conn = described_class.new(name: 'test', transport: :http)
      expect { conn.connect }.to raise_error(ArgumentError, /url/)
    end

    context 'with stdio transport' do
      let(:mock_transport) { instance_double(MCP::Client::Stdio) }
      let(:mock_client) { instance_double(MCP::Client) }
      let(:mcp_tool) do
        MCP::Client::Tool.new(name: 'echo', description: 'echo tool', input_schema: {})
      end

      before do
        allow(MCP::Client::Stdio).to receive(:new).and_return(mock_transport)
        allow(MCP::Client).to receive(:new).and_return(mock_client)
        allow(mock_client).to receive(:tools).and_return([mcp_tool])
      end

      it 'creates an MCP::Client::Stdio transport and verifies via tools/list' do
        conn = described_class.new(name: 'test', transport: :stdio, command: 'npx some-server')
        conn.connect

        expect(MCP::Client::Stdio).to have_received(:new).with(command: 'npx', args: ['some-server'])
        expect(MCP::Client).to have_received(:new).with(transport: mock_transport)
        expect(mock_client).to have_received(:tools)
        expect(conn.connected?).to be(true)
      end

      it 'remains disconnected when handshake fails' do
        allow(mock_client).to receive(:tools).and_raise(
          MCP::Client::ServerError.new('handshake fail', code: -1)
        )
        conn = described_class.new(name: 'test', transport: :stdio, command: 'echo')
        expect { conn.connect }.to raise_error(Legion::MCP::Client::ConnectionError, /handshake/)
        expect(conn.connected?).to be(false)
      end
    end

    context 'with http transport' do
      let(:mock_transport) { instance_double(MCP::Client::HTTP) }
      let(:mock_client) { instance_double(MCP::Client) }

      before do
        allow(MCP::Client::HTTP).to receive(:new).and_return(mock_transport)
        allow(MCP::Client).to receive(:new).and_return(mock_client)
        allow(mock_client).to receive(:tools).and_return([])
      end

      it 'creates an MCP::Client::HTTP transport and verifies via tools/list' do
        conn = described_class.new(name: 'test', transport: :http, url: 'http://localhost:8080/mcp')
        conn.connect

        expect(MCP::Client::HTTP).to have_received(:new).with(url: 'http://localhost:8080/mcp', headers: {})
        expect(conn.connected?).to be(true)
      end

      it 'passes auth header when configured' do
        conn = described_class.new(
          name: 'test',
          transport: :http,
          url: 'http://localhost:8080/mcp',
          auth: 'Bearer tok123'
        )
        conn.connect

        expect(MCP::Client::HTTP).to have_received(:new).with(
          url: 'http://localhost:8080/mcp',
          headers: { 'Authorization' => 'Bearer tok123' }
        )
      end
    end
  end

  describe '#disconnect' do
    let(:mock_transport) { instance_double(MCP::Client::Stdio, close: nil) }
    let(:mock_client) { instance_double(MCP::Client) }

    before do
      allow(MCP::Client::Stdio).to receive(:new).and_return(mock_transport)
      allow(MCP::Client).to receive(:new).and_return(mock_client)
      allow(mock_client).to receive(:tools).and_return([])
    end

    it 'closes the transport and resets state' do
      conn = described_class.new(name: 'test', transport: :stdio, command: 'echo')
      conn.connect
      expect(conn.connected?).to be(true)

      conn.disconnect
      expect(conn.connected?).to be(false)
      expect(mock_transport).to have_received(:close)
    end
  end

  describe '#tools' do
    let(:mock_transport) { instance_double(MCP::Client::Stdio, close: nil) }
    let(:mock_client) { instance_double(MCP::Client) }
    let(:mcp_tool) do
      MCP::Client::Tool.new(name: 'list_files', description: 'List files', input_schema: {})
    end

    before do
      allow(MCP::Client::Stdio).to receive(:new).and_return(mock_transport)
      allow(MCP::Client).to receive(:new).and_return(mock_client)
      allow(mock_client).to receive(:tools).and_return([mcp_tool])
    end

    it 'returns tools from the remote server' do
      conn = described_class.new(name: 'test', transport: :stdio, command: 'echo')
      conn.connect
      tools = conn.tools
      expect(tools.size).to eq(1)
      expect(tools.first[:name]).to eq('list_files')
      expect(tools.first[:description]).to eq('List files')
    end

    it 'caches tools with TTL' do
      conn = described_class.new(name: 'test', transport: :stdio, command: 'echo')
      conn.connect
      conn.tools
      conn.tools # second call should use cache
      # connect calls tools once for verify, tools() does not call again due to cache
      expect(mock_client).to have_received(:tools).once
    end

    it 'refreshes cache when forced' do
      conn = described_class.new(name: 'test', transport: :stdio, command: 'echo')
      conn.connect
      conn.tools
      conn.tools(force_refresh: true)
      # once for verify_connection!, once for force_refresh
      expect(mock_client).to have_received(:tools).twice
    end
  end

  describe '#call_tool' do
    let(:mock_transport) { instance_double(MCP::Client::Stdio, close: nil) }
    let(:mock_client) { instance_double(MCP::Client) }

    before do
      allow(MCP::Client::Stdio).to receive(:new).and_return(mock_transport)
      allow(MCP::Client).to receive(:new).and_return(mock_client)
      allow(mock_client).to receive(:tools).and_return([])
    end

    it 'executes a tool and returns result' do
      allow(mock_client).to receive(:call_tool).and_return(
        { 'result' => { 'content' => [{ 'type' => 'text', 'text' => '["file1.rb"]' }], 'isError' => false } }
      )

      conn = described_class.new(name: 'test', transport: :stdio, command: 'echo')
      conn.connect
      result = conn.call_tool(name: 'list_files', arguments: { path: '.' })
      expect(result[:content]).to eq([{ 'type' => 'text', 'text' => '["file1.rb"]' }])
      expect(result[:error]).to be(false)
    end

    it 'returns error payload when server returns a tool error' do
      allow(mock_client).to receive(:call_tool).and_raise(
        MCP::Client::ServerError.new('tool not found', code: -32_601)
      )

      conn = described_class.new(name: 'test', transport: :stdio, command: 'echo')
      conn.connect
      result = conn.call_tool(name: 'missing_tool', arguments: {})
      expect(result[:error]).to be(true)
      expect(result[:content].first[:text]).to include('tool not found')
    end

    it 'raises ConnectionError on transport failure' do
      allow(mock_client).to receive(:call_tool).and_raise(
        MCP::Client::RequestHandlerError.new('pipe broken', {})
      )

      conn = described_class.new(name: 'test', transport: :stdio, command: 'echo')
      conn.connect
      expect { conn.call_tool(name: 'list_files', arguments: {}) }
        .to raise_error(Legion::MCP::Client::ConnectionError, /pipe broken/)
    end

    it 'logs tool call start and completion' do
      allow(mock_client).to receive(:call_tool).and_return(
        { 'result' => { 'content' => [{ 'type' => 'text', 'text' => 'ok' }] } }
      )

      conn = described_class.new(name: 'test', transport: :stdio, command: 'echo')
      conn.connect
      conn.call_tool(name: 'list_files', arguments: { path: '.' })

      expect(logger).to have_received(:info).with(include('[mcp] client.tool_call.start', 'tool_name="list_files"'))
      expect(logger).to have_received(:info).with(include('[mcp] client.tool_call.complete', 'tool_name="list_files"'))
    end
  end
end
