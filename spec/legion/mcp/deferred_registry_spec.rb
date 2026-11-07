# frozen_string_literal: true

require 'spec_helper'
require 'legion/mcp'

RSpec.describe Legion::MCP::DeferredRegistry do
  let(:always_loaded_tool) do
    Class.new(MCP::Tool) do
      tool_name 'legion.run_task'
      title 'Run task'
      description 'Execute a task.'
      input_schema(properties: { task: { type: 'string' } }, required: ['task'])
    end
  end

  let(:deferred_tool) do
    Class.new(MCP::Tool) do
      tool_name 'legion.rbac_check'
      title 'Check permissions'
      description 'Check RBAC permissions.'
      input_schema(properties: { principal: { type: 'string' } }, required: ['principal'])
    end
  end

  describe '.deferred?' do
    it 'returns false for always-loaded tools' do
      expect(described_class.deferred?(always_loaded_tool)).to be false
    end

    it 'returns true for non-always-loaded tools' do
      expect(described_class.deferred?(deferred_tool)).to be true
    end

    it 'returns false for all tools when disabled' do
      Legion::Settings[:mcp][:deferred_loading][:enabled] = false
      expect(described_class.deferred?(deferred_tool)).to be false
    end
  end

  describe '.build_tools_list' do
    let(:tools) { [always_loaded_tool, deferred_tool] }

    it 'serializes authoritative argument schemas for full and deferred descriptors' do
      entries = Legion::JSON.load(Legion::JSON.dump(described_class.build_tools_list(tools)))

      expect(entries.map { |entry| entry.fetch(:inputSchema) }).to match(
        [
          include(type: 'object', properties: { task: { type: 'string' } }, required: ['task']),
          include(type: 'object', properties: { principal: { type: 'string' } }, required: ['principal'])
        ]
      )
      expect(entries.first.fetch(:title)).to eq('Run task')
      expect(entries.last).not_to have_key(:title)
      expect(entries.last.fetch(:name)).to eq('legion.rbac_check')
    end

    [nil, {}, { deferred_loading: nil }, { deferred_loading: { enabled: nil, always_loaded: nil } }].each do |settings|
      context "with nullable or absent optional configuration #{settings.inspect}" do
        before { Legion::Settings.loader.settings[:mcp] = settings }

        it 'lists valid schemas while retaining default deferral boundaries' do
          result = described_class.build_tools_list(tools)

          expect(result.map { |entry| entry.fetch(:inputSchema).fetch(:required) }).to eq([['task'], ['principal']])
          expect(result.first.fetch(:title)).to eq('Run task')
          expect(result.last).not_to have_key(:title)
          expect(described_class.deferred?(always_loaded_tool)).to be false
          expect(described_class.deferred?(deferred_tool)).to be true
        end
      end
    end

    it 'returns all full entries when deferred loading is explicitly disabled' do
      Legion::Settings[:mcp][:deferred_loading][:enabled] = false
      result = described_class.build_tools_list(tools)

      expect(result.last.fetch(:title)).to eq('Check permissions')
      expect(described_class.deferred?(deferred_tool)).to be false
    end

    it 'uses updated always-loaded settings on the next tool listing without losing schemas' do
      initial = described_class.build_tools_list(tools)
      expect(initial.last).not_to have_key(:title)

      Legion::Settings[:mcp][:deferred_loading][:always_loaded] = ['legion.rbac_check']
      promoted = described_class.build_tools_list(tools)
      expect(promoted.last.fetch(:title)).to eq('Check permissions')
      expect(described_class.deferred?(deferred_tool)).to be false

      Legion::Settings[:mcp][:deferred_loading][:always_loaded] = []
      demoted = described_class.build_tools_list(tools)
      expect(demoted).to eq(initial)
      expect(described_class.deferred?(deferred_tool)).to be true
      expect(demoted.map { |entry| entry.fetch(:inputSchema) }).to eq(promoted.map { |entry| entry.fetch(:inputSchema) })
    end

    it 'applies live extension declarations using the adapted tool name' do
      declarations = []
      allow(Legion::Settings::Extensions).to receive(:filter_tools).with(deferred: false).and_return(declarations)
      extension_tool = Legion::MCP::ToolAdapter.from_legion_tool(deferred_tool)
      expect(described_class.deferred?(extension_tool)).to be true

      declarations << { name: deferred_tool.tool_name }
      expect(described_class.deferred?(extension_tool)).to be false
      schema = described_class.build_tools_list([extension_tool]).first.fetch(:inputSchema)
      expect(schema.fetch(:required)).to eq(['principal'])

      declarations.clear
      expect(described_class.deferred?(extension_tool)).to be true
    end
  end

  describe '.resolve_schemas' do
    let(:tools) { [always_loaded_tool, deferred_tool] }

    it 'returns full schemas for matching tool names' do
      schemas = described_class.resolve_schemas(['legion.rbac_check'], tools)
      expect(schemas.map { |entry| entry.fetch(:name) }).to eq(['legion.rbac_check'])
      expect(schemas.first.fetch(:inputSchema).fetch(:required)).to eq(['principal'])
    end

    it 'returns empty array for non-matching names' do
      schemas = described_class.resolve_schemas(['legion.nonexistent'], tools)
      expect(schemas).to be_empty
    end

    it 'returns multiple schemas for multiple names' do
      schemas = described_class.resolve_schemas(%w[legion.run_task legion.rbac_check], tools)
      expect(schemas.map { |entry| entry.fetch(:name) }).to contain_exactly('legion.run_task', 'legion.rbac_check')
    end
  end
end
