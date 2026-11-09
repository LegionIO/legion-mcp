# frozen_string_literal: true

require 'spec_helper'
require 'legion/mcp'

RSpec.describe Legion::MCP::Server do

  before do
    allow(Legion::Settings).to receive(:dig).and_return(nil)
  end

  describe '.build' do
    subject(:server) { described_class.build }

    it 'returns an MCP::Server instance' do
      expect(server).to be_a(MCP::Server)
    end

    it 'registers the correct name' do
      expect(server.name).to eq('legion')
    end

    it 'registers the correct version' do
      expect(server.version).to eq(Legion::MCP::VERSION)
    end

    it 'advertises MCP tools in the protocol list result object' do
      request = Legion::JSON.dump({ jsonrpc: '2.0', id: 1, method: 'tools/list', params: {} })
      response = Legion::JSON.load(server.handle_json(request))
      names = response.fetch(:result).fetch(:tools).map { |tool| tool.fetch(:name) }

      expect(names).to include('legion.plan', 'legion.tools')
    end



    context 'with governance enabled' do
      before do
        allow(Legion::Settings).to receive(:dig).and_return(nil)
        allow(Legion::Settings).to receive(:dig).with(:mcp, :governance, :enabled).and_return(true)
        allow(Legion::Settings).to receive(:dig).with(:mcp, :governance, :tool_risk_tiers).and_return({})
      end

      it 'excludes high and medium tier tools for low-tier identity' do
        server = described_class.build(identity: { risk_tier: :low })
        high_tools = Legion::MCP::ToolGovernance::DEFAULT_TOOL_TIERS.select { |_, v| %i[high medium].include?(v) }.keys
        expect(server.tools.keys & high_tools).to be_empty
      end

      it 'includes all MCP-specific tools for high-tier identity' do
        server = described_class.build(identity: { risk_tier: :high })
        expect(server.tools.keys).to include('legion.plan', 'legion.tools')
      end
    end
  end

  describe '.build_filtered_tool_list with governance' do
    let(:low_tool) do
      Class.new(MCP::Tool) do
        tool_name 'legion.list_tasks'
        description 'List tasks'
        input_schema(properties: {})
        def self.call(**) = MCP::Tool::Response.new([{ type: 'text', text: '{}' }])
      end
    end

    let(:high_tool) do
      Class.new(MCP::Tool) do
        tool_name 'legion.worker_lifecycle'
        description 'Manage workers'
        input_schema(properties: {})
        def self.call(**) = MCP::Tool::Response.new([{ type: 'text', text: '{}' }])
      end
    end

    before do
      described_class.instance_variable_set(:@tool_registry, Concurrent::Array.new([low_tool, high_tool]))
    end

    after do
      described_class.rebuild_tool_registry
      described_class.instance_variable_set(:@current_identity, nil)
    end

    context 'when governance is enabled' do
      before do
        allow(Legion::Settings).to receive(:dig).with(:mcp, :governance, :enabled).and_return(true)
        allow(Legion::Settings).to receive(:dig).with(:mcp, :governance, :tool_risk_tiers).and_return({})
      end

      it 'excludes high-tier tools for low-tier identity' do
        described_class.instance_variable_set(:@current_identity, { risk_tier: :low })
        result = described_class.build_filtered_tool_list
        names = result.map(&:tool_name)
        expect(names).to include('legion.list_tasks')
        expect(names).not_to include('legion.worker_lifecycle')
      end

      it 'includes all tools for high-tier identity' do
        described_class.instance_variable_set(:@current_identity, { risk_tier: :high })
        result = described_class.build_filtered_tool_list
        names = result.map(&:tool_name)
        expect(names).to include('legion.list_tasks', 'legion.worker_lifecycle')
      end
    end

    context 'when governance is disabled' do
      it 'returns all tools regardless of identity' do
        described_class.instance_variable_set(:@current_identity, { risk_tier: :low })
        result = described_class.build_filtered_tool_list
        names = result.map(&:tool_name)
        expect(names).to include('legion.list_tasks', 'legion.worker_lifecycle')
      end
    end
  end

  describe '.tool_registry' do
    it 'returns an array containing MCP-specific tools' do
      registry = Legion::MCP::Server.tool_registry
      expect(registry).to include(Legion::MCP::Tools::PlanAction)
      expect(registry).to include(Legion::MCP::Tools::DiscoverTools)
    end

  end

  describe '.register_tool' do
    after { Legion::MCP::Server.unregister_tool('test.dynamic_tool') }

    it 'adds a tool class to the registry' do
      tool_class = Class.new(MCP::Tool) do
        tool_name 'test.dynamic_tool'
        description 'A test tool'
        input_schema(properties: {})
        def self.call(**) = MCP::Tool::Response.new([{ type: 'text', text: '{}' }])
      end

      Legion::MCP::Server.register_tool(tool_class)
      expect(Legion::MCP::Server.tool_registry.map(&:tool_name)).to include('test.dynamic_tool')
    end

    it 'does not add duplicate tool names' do
      tool_class = Class.new(MCP::Tool) do
        tool_name 'test.dynamic_tool'
        description 'A test tool'
        input_schema(properties: {})
        def self.call(**) = MCP::Tool::Response.new([{ type: 'text', text: '{}' }])
      end

      Legion::MCP::Server.register_tool(tool_class)
      Legion::MCP::Server.register_tool(tool_class)
      count = Legion::MCP::Server.tool_registry.count { |tc| tc.tool_name == 'test.dynamic_tool' }
      expect(count).to eq(1)
    end
  end

  describe '.unregister_tool' do
    it 'removes a tool by name' do
      tool_class = Class.new(MCP::Tool) do
        tool_name 'test.removable_tool'
        description 'removable'
        input_schema(properties: {})
        def self.call(**) = MCP::Tool::Response.new([{ type: 'text', text: '{}' }])
      end

      Legion::MCP::Server.register_tool(tool_class)
      Legion::MCP::Server.unregister_tool('test.removable_tool')
      expect(Legion::MCP::Server.tool_registry.map(&:tool_name)).not_to include('test.removable_tool')
    end
  end
end
