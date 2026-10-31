# frozen_string_literal: true

require 'spec_helper'
require 'legion/mcp'

RSpec.describe 'Server tracing context integration' do
  let(:probe_state) { { fail: false, contexts: [] } }
  let(:server) do
    state = probe_state
    Legion::MCP::Server.build.tap do |built|
      built.define_tool(name: 'test.tracing_probe', input_schema: { properties: {} }) do |**|
        context = Legion::MCP::TracingContext.current
        state[:contexts] << context
        raise 'probe failure' if state[:fail]

        MCP::Tool::Response.new([{ type: 'text', text: Legion::JSON.dump(context) }])
      end
    end
  end

  around do |example|
    settings = Legion::Settings.loader.settings
    previous = settings[:mcp]
    settings[:mcp] = {}
    example.run
  ensure
    settings[:mcp] = previous
    Legion::MCP::TracingContext.clear
  end

  def call_probe(name: 'test.tracing_probe')
    request = Legion::JSON.dump({
                                  jsonrpc: '2.0',
                                  id:      1,
                                  method:  'tools/call',
                                  params:  { name: name, arguments: {} }
                                })
    Legion::JSON.load(server.handle_json(request))
  end

  def trace_from(response:)
    text = response.fetch(:result).fetch(:content).first.fetch(:text)
    Legion::JSON.load(text)
  end

  it 'preserves session tracing while assigning distinct identities to actual tool calls' do
    first = trace_from(response: call_probe)
    second = trace_from(response: call_probe)

    expect(first).to include(:conversation_id, :request_id, :exchange_id, :tool_call_id, :trace_id)
    expect(first.values).to all(be_a(String))
    expect(first.fetch(:trace_id)).to match(/\A[0-9a-f]{32}\z/)
    expect(second.slice(:conversation_id, :trace_id)).to eq(first.slice(:conversation_id, :trace_id))
    %i[request_id exchange_id tool_call_id].each do |key|
      expect(second.fetch(key)).not_to eq(first.fetch(key))
    end
    expect(Legion::MCP::TracingContext.current.values).to all(be_nil)
  end

  it 'clears failed tool tracing before a subsequent successful invocation' do
    probe_state[:fail] = true
    failure = call_probe

    expect(failure.fetch(:error).fetch(:code)).to eq(-32_603)
    failed_context = probe_state[:contexts].fetch(0)
    expect(failed_context.fetch(:request_id)).to be_a(String)
    expect(Legion::MCP::TracingContext.current.values).to all(be_nil)

    probe_state[:fail] = false
    recovered = trace_from(response: call_probe)
    expect(recovered.fetch(:request_id)).not_to eq(failed_context.fetch(:request_id))
    expect(Legion::MCP::TracingContext.current.values).to all(be_nil)
  end

  it 'preserves the SDK error for an unknown tool without retaining request context' do
    response = call_probe(name: 'test.unregistered_probe')

    expect(response.fetch(:error).fetch(:code)).to eq(-32_602)
    expect(probe_state[:contexts]).to eq([])
    expect(Legion::MCP::TracingContext.current.values).to all(be_nil)
  end
end
