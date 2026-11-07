# frozen_string_literal: true

require 'spec_helper'
require 'legion/mcp'
require 'mcp/server_session'
require 'timeout'

RSpec.describe 'Server live authorization' do
  let(:probe_state) { { calls: [], fail: false, cancel: false } }
  let(:identity) { { user_id: 'reader', role: :reader, risk_tier: :low } }
  let(:settings) do
    {
      roles: { reader: { tools: ['*'] }, admin: { tools: ['*'] } },
      governance: { enabled: false, tool_risk_tiers: {} }
    }
  end
  let(:probe) do
    state = probe_state
    Class.new(MCP::Tool) do
      tool_name 'test.authorization_probe'
      description 'Record an authorized invocation.'
      input_schema(properties: { value: { type: 'string' } }, required: ['value'])
      define_singleton_method(:call) do |value:, server_context:|
        server_context.require_scopes!('probe:invoke') if state[:require_scope]
        state[:calls] << { value: value, context: server_context, tracing: Legion::MCP::TracingContext.current }
        raise 'authorization probe failure' if state[:fail]

        if state[:cancel]
          server_context.cancellation.cancel(reason: 'probe cancelled')
          server_context.raise_if_cancelled!
        end
        MCP::Tool::Response.new([{ type: 'text', text: value }])
      end
    end
  end
  let(:server) { Legion::MCP::Server.build(identity: identity) }

  around do |example|
    server_module = Legion::MCP::Server
    variables = %i[@tool_registry @current_identity @conversation_id @trace_id]
    previous = variables.to_h { |name| [name, server_module.instance_variable_get(name)] }
    previous_settings = Legion::Settings.loader.settings[:mcp]
    previous_instrumentation = MCP.configuration.instrumentation_callback
    previous_tracing = Legion::MCP::TracingContext::THREAD_KEYS.to_h { |key| [key, Thread.current[key]] }
    Legion::Settings.loader.settings[:mcp] = settings
    example.run
  ensure
    previous.each { |name, value| server_module.instance_variable_set(name, value) }
    Legion::Settings.loader.settings[:mcp] = previous_settings
    MCP.configuration.instrumentation_callback = previous_instrumentation
    previous_tracing.each { |key, value| Thread.current[key] = value }
  end

  before do
    # Keep the SDK build and request dispatch real without loading external extensions or caches.
    allow(Legion::MCP::Server).to receive_messages(
      run_function_discovery: nil, rebuild_tool_registry: nil,
      register_mcp_tools_in_settings_extensions: nil, populate_embedding_index: nil,
      hydrate_override_confidence: nil, tool_registry: [probe, Legion::MCP::Tools::DiscoverTools]
    )
    allow(Legion::MCP::Patterns::Store).to receive(:hydrate_from_l2)
    allow(Legion::MCP::ColdStart).to receive(:load_community_patterns)
    allow(Legion::MCP::Resources::RunnerCatalog).to receive(:register)
    allow(Legion::MCP::Resources::ExtensionInfo).to receive_messages(
      static_resources: [], resource_templates: [], register_read_handler: nil
    )
    allow(Legion::MCP::Observer).to receive(:record)
    allow(Legion::MCP::Audit).to receive(:emit_governance)
    allow(Legion::MCP::Audit).to receive(:emit_tool_call)
  end

  def rpc(server:, method:, params: {}, **options)
    request = Legion::JSON.dump({ jsonrpc: '2.0', id: 7, method: method, params: params })
    response = server.handle_json(request, **options)
    Legion::JSON.load(response) if response
  end

  def invoke(server:, name: 'test.authorization_probe', arguments: { value: 'executed' }, meta: {}, **options)
    rpc(server: server, method: 'tools/call', params: { name: name, arguments: arguments, _meta: meta }, **options)
  end

  def listed_names(server:)
    rpc(server: server, method: 'tools/list').fetch(:result).fetch(:tools).map { |tool| tool.fetch(:name) }
  end

  it 'enforces grant, revoke, and regrant on one retained server for both listing and direct calls' do
    expect(listed_names(server: server)).to include(probe.tool_name)
    expect(invoke(server: server).fetch(:result).fetch(:isError)).to be false

    settings[:roles][:reader][:tools] = []
    expect(listed_names(server: server)).not_to include(probe.tool_name)
    denied = invoke(server: server).fetch(:result)
    expect(denied.fetch(:isError)).to be true
    expect(denied.fetch(:content).first.fetch(:text)).to include('Permission denied')
    expect(probe_state[:calls].size).to eq(1)
    expect(Legion::MCP::TracingContext.current.values).to all(be_nil)
    expect(Legion::MCP::Audit).to have_received(:emit_tool_call).with(hash_including(caller: identity, status: :error))
    expect(Legion::MCP::Audit).to have_received(:emit_governance).with(hash_including(identity: identity)).at_least(:once)

    settings[:roles][:reader][:tools] = [probe.tool_name]
    expect(listed_names(server: server)).to include(probe.tool_name)
    expect(invoke(server: server).fetch(:result).fetch(:isError)).to be false
    expect(probe_state[:calls].size).to eq(2)
  end

  {
    'symbol role false' => { reader: false, 'reader' => { tools: ['*'] } },
    'symbol tools false' => { reader: { tools: false, 'tools' => ['*'] } },
    'string role false' => { reader: nil, 'reader' => false },
    'string tools false' => { 'reader' => { tools: nil, 'tools' => false } }
  }.each do |label, roles|
    it "denies direct calls after changing policy to #{label}" do
      expect(invoke(server: server).fetch(:result).fetch(:isError)).to be false
      settings[:roles] = roles

      expect(listed_names(server: server)).not_to include(probe.tool_name)
      expect(invoke(server: server).fetch(:result).fetch(:isError)).to be true
      expect(probe_state[:calls].size).to eq(1)
    end
  end

  it 'reads changed governance enablement and risk-tier mappings on each invocation' do
    expect(invoke(server: server).fetch(:result).fetch(:isError)).to be false
    settings[:governance] = { enabled: true, tool_risk_tiers: { probe.tool_name => :high } }

    expect(listed_names(server: server)).not_to include(probe.tool_name)
    expect(invoke(server: server).fetch(:result).fetch(:isError)).to be true
    expect(probe_state[:calls].size).to eq(1)

    settings[:governance][:tool_risk_tiers][probe.tool_name] = :low
    expect(listed_names(server: server)).to include(probe.tool_name)
    expect(invoke(server: server).fetch(:result).fetch(:isError)).to be false
    expect(probe_state[:calls].size).to eq(2)
  end

  it 'keeps each retained server authority, schema discovery, tracing, and audit identity separate' do
    reader = server
    reader_context = reader.server_context
    admin_identity = { user_id: 'admin', role: :admin, risk_tier: :high }
    admin = Legion::MCP::Server.build(identity: admin_identity)
    settings[:roles][:reader][:tools] = ['legion.tools']

    expect(listed_names(server: reader)).not_to include(probe.tool_name)
    expect(listed_names(server: admin)).to include(probe.tool_name)
    expect(invoke(server: reader).fetch(:result).fetch(:isError)).to be true
    expect(invoke(server: admin).fetch(:result).fetch(:isError)).to be false
    expect(probe_state[:calls].map { |call| call[:context][:identity] }).to eq([admin_identity])

    discovery_arguments = { tool_names: [probe.tool_name], schema: true }
    expect(invoke(server: reader, name: 'legion.tools', arguments: discovery_arguments).fetch(:result).fetch(:isError)).to be true
    expect(invoke(server: admin, name: 'legion.tools', arguments: discovery_arguments).fetch(:result).fetch(:isError)).to be false
    expect(Legion::MCP::Audit).to have_received(:emit_tool_call).with(
      hash_including(caller: identity, conversation_id: reader_context[:conversation_id], trace_id: reader_context[:trace_id], status: :error)
    ).at_least(:once)
    expect(Legion::MCP::Audit).to have_received(:emit_tool_call).with(hash_including(caller: admin_identity, status: :success)).at_least(:once)

    settings[:roles][:reader][:tools] = ['*']
    expect(invoke(server: reader).fetch(:result).fetch(:isError)).to be false
    expect(probe_state[:calls].last[:context][:identity]).to eq(identity)
    expect(probe_state[:calls].last[:tracing]).to include(reader_context.slice(:conversation_id, :trace_id))
    expect(Legion::MCP::TracingContext.current.values).to all(be_nil)
  end

  it 'keeps invocation tracing distinct when server builds overlap' do
    prepared = Queue.new
    release = Queue.new
    threads = []
    allow(Legion::MCP::Server).to receive(:prepare_build).and_wrap_original do |original, *args, **kwargs|
      original.call(*args, **kwargs)
      prepared << true
      release.pop
    end

    %w[first second].each do |user_id|
      threads << Thread.new { Legion::MCP::Server.build(identity: identity.merge(user_id: user_id)) }
    end
    Timeout.timeout(10) { 2.times { prepared.pop } }
    2.times { release << true }
    threads.map(&:value).each { |built| expect(invoke(server: built).fetch(:result).fetch(:isError)).to be false }

    calls = probe_state[:calls]
    expect(calls.map { |call| call[:context][:identity][:user_id] }).to eq(%w[first second])
    expect(calls.first[:tracing][:conversation_id]).not_to eq(calls.last[:tracing][:conversation_id])
    expect(calls.first[:tracing][:trace_id]).not_to eq(calls.last[:tracing][:trace_id])
  ensure
    threads&.each { |thread| thread.kill.join }
  end

  it 'accepts a nullable mcp parent without losing the server identity' do
    built = server
    Legion::Settings.loader.settings[:mcp] = nil

    expect(listed_names(server: built)).to include(probe.tool_name)
    expect(invoke(server: built).fetch(:result).fetch(:isError)).to be false
    expect(probe_state[:calls].last[:context][:identity]).to eq(identity)
  end

  it 'preserves SDK unknown-tool and argument errors with tracing cleanup' do
    unknown = invoke(server: server, name: 'test.unknown')
    expect(unknown.fetch(:error).fetch(:code)).to eq(-32_602)
    expect(Legion::MCP::TracingContext.current.values).to all(be_nil)

    invalid = invoke(server: server, arguments: {})
    expect(invalid.fetch(:result).fetch(:isError)).to be true
    expect(probe_state[:calls]).to be_empty
    expect(Legion::MCP::TracingContext.current.values).to all(be_nil)
  end

  it 'preserves SDK tool exceptions and cleans tracing before the next call' do
    probe_state[:fail] = true
    expect(invoke(server: server).fetch(:error).fetch(:code)).to eq(-32_603)
    expect(Legion::MCP::TracingContext.current.values).to all(be_nil)

    probe_state[:fail] = false
    expect(invoke(server: server).fetch(:result).fetch(:isError)).to be false
    expect(Legion::MCP::TracingContext.current.values).to all(be_nil)
  end

  it 'enforces OAuth scopes through a real session and preserves cancellation cleanup' do
    probe_state[:require_scope] = true
    session = MCP::ServerSession.new(server: server, transport: nil)
    rpc(server: server, method: 'initialize', session: session,
        params: { protocolVersion: '2025-11-25', capabilities: {}, clientInfo: { name: 'authorization-spec', version: '1' } })

    denied = invoke(server: server, session: session)
    expect(denied.fetch(:error).fetch(:code)).to eq(-32_600)
    expect(probe_state[:calls]).to be_empty
    expect(Legion::MCP::TracingContext.current.values).to all(be_nil)

    token = MCP::Server::OAuth::AccessToken.new(token: 'spec-token', scopes: ['probe:invoke'])
    response = invoke(server: server, session: session, auth_info: token)
    expect(response.fetch(:result).fetch(:isError)).to be false
    expect(probe_state[:calls].size).to eq(1)
    expect(session.in_flight?(7)).to be false

    probe_state[:cancel] = true
    expect(invoke(server: server, session: session, auth_info: token)).to be_nil
    expect(session.in_flight?(7)).to be false
    expect(Legion::MCP::TracingContext.current.values).to all(be_nil)
  end
end
