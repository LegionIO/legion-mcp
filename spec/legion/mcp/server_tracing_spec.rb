# frozen_string_literal: true

require 'spec_helper'
require 'legion/mcp'

RSpec.describe 'Server tracing context integration' do
  let(:logger) { spy('logger') }
  let(:captured_context) { {} }

  before do
    allow(Legion::Settings).to receive(:dig).and_return(nil)
    allow(Legion::MCP::Server).to receive(:log).and_return(logger)

    @tracing_tool = Class.new(MCP::Tool) do
      tool_name 'test.tracing_probe'
      description 'Captures tracing context during execution'
      input_schema(properties: { msg: { type: 'string' } })
    end

    ctx = captured_context
    @tracing_tool.define_singleton_method(:call) do |**_params|
      Legion::MCP::TracingContext::THREAD_KEYS.each do |key|
        short = key.to_s.delete_prefix('legion_mcp_').to_sym
        ctx[short] = Thread.current[key]
      end
      MCP::Tool::Response.new([{ type: 'text', text: 'ok' }])
    end
  end

  after { Legion::MCP::TracingContext.clear }

  def build_server_with_probe
    server = Legion::MCP::Server.build
    server.tools['test.tracing_probe'] = @tracing_tool
    server
  end

  def call_tool_via_handle(server, tool_name, arguments = {})
    jsonrpc_request = {
      jsonrpc: '2.0',
      id:      1,
      method:  'tools/call',
      params:  { name: tool_name, arguments: arguments }
    }
    server.handle(jsonrpc_request)
  end

  describe 'conversation_id and trace_id on Server module' do
    it 'generates conversation_id on build' do
      build_server_with_probe
      expect(Legion::MCP::Server.conversation_id).to match(/\Amcp_/)
    end

    it 'generates trace_id on build' do
      build_server_with_probe
      expect(Legion::MCP::Server.trace_id).to match(/\A[0-9a-f]{32}\z/)
    end

    it 'generates new IDs on each build' do
      build_server_with_probe
      first_id = Legion::MCP::Server.conversation_id
      build_server_with_probe
      second_id = Legion::MCP::Server.conversation_id
      expect(first_id).not_to eq(second_id)
    end
  end

  describe 'Thread locals during tool execution' do
    it 'sets all tracing IDs during tool call' do
      server = build_server_with_probe
      call_tool_via_handle(server, 'test.tracing_probe', { msg: 'hello' })

      expect(captured_context[:conversation_id]).to match(/\Amcp_/)
      expect(captured_context[:request_id]).to match(/\Areq_/)
      expect(captured_context[:exchange_id]).to match(/\Aexch_/)
      expect(captured_context[:tool_call_id]).to match(/\Acall_/)
      expect(captured_context[:trace_id]).to match(/\A[0-9a-f]{32}\z/)
    end

    it 'clears Thread locals after tool execution' do
      server = build_server_with_probe
      call_tool_via_handle(server, 'test.tracing_probe', { msg: 'hello' })

      Legion::MCP::TracingContext::THREAD_KEYS.each do |key|
        expect(Thread.current[key]).to be_nil
      end
    end

    it 'clears Thread locals even when tool raises' do
      @tracing_tool.define_singleton_method(:call) { |**_| raise 'boom' }
      server = build_server_with_probe
      call_tool_via_handle(server, 'test.tracing_probe', { msg: 'hello' })

      Legion::MCP::TracingContext::THREAD_KEYS.each do |key|
        expect(Thread.current[key]).to be_nil
      end
    end

    it 'generates unique exchange_id per tool call' do
      server = build_server_with_probe
      exchange_ids = []

      2.times do
        call_tool_via_handle(server, 'test.tracing_probe')
        exchange_ids << captured_context[:exchange_id]
      end

      expect(exchange_ids.uniq.size).to eq(2)
    end

    it 'shares conversation_id across tool calls in one session' do
      server = build_server_with_probe
      conversation_ids = []

      2.times do
        call_tool_via_handle(server, 'test.tracing_probe')
        conversation_ids << captured_context[:conversation_id]
      end

      expect(conversation_ids.uniq.size).to eq(1)
    end

    it 'shares trace_id across tool calls in one session' do
      server = build_server_with_probe
      trace_ids = []

      2.times do
        call_tool_via_handle(server, 'test.tracing_probe')
        trace_ids << captured_context[:trace_id]
      end

      expect(trace_ids.uniq.size).to eq(1)
    end
  end
end
