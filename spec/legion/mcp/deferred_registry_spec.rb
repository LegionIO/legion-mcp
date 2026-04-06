# frozen_string_literal: true

require 'spec_helper'
require 'legion/mcp'

RSpec.describe Legion::MCP::DeferredRegistry do
  let(:always_loaded_tool) do
    Class.new(MCP::Tool) do
      tool_name 'legion.run_task'
      description 'Execute a task.'
      input_schema(properties: { task: { type: 'string' } }, required: ['task'])
    end
  end

  let(:deferred_tool) do
    Class.new(MCP::Tool) do
      tool_name 'legion.rbac_check'
      description 'Check RBAC permissions.'
      input_schema(properties: { principal: { type: 'string' } }, required: ['principal'])
    end
  end

  before do
    described_class.reset_cache!
    allow(Legion::Settings).to receive(:dig).and_return(nil)
  end

  describe '.enabled?' do
    it 'defaults to true when setting is nil' do
      expect(described_class.enabled?).to be true
    end

    it 'returns false when explicitly disabled' do
      allow(Legion::Settings).to receive(:dig).with(:mcp, :deferred_loading, :enabled).and_return(false)
      expect(described_class.enabled?).to be false
    end

    it 'returns true when explicitly enabled' do
      allow(Legion::Settings).to receive(:dig).with(:mcp, :deferred_loading, :enabled).and_return(true)
      expect(described_class.enabled?).to be true
    end
  end

  describe '.always_loaded_tools' do
    it 'includes the default always-loaded tools' do
      expect(described_class.always_loaded_tools).to include('legion.do', 'legion.tools', 'legion.run_task')
    end

    it 'merges custom always-loaded tools from settings' do
      allow(Legion::Settings).to receive(:dig).with(:mcp, :deferred_loading, :always_loaded).and_return(['legion.custom_tool'])
      expect(described_class.always_loaded_tools).to include('legion.custom_tool')
    end

    it 'preserves defaults when custom list is provided' do
      allow(Legion::Settings).to receive(:dig).with(:mcp, :deferred_loading, :always_loaded).and_return(['legion.custom_tool'])
      expect(described_class.always_loaded_tools).to include('legion.do')
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
      allow(Legion::Settings).to receive(:dig).with(:mcp, :deferred_loading, :enabled).and_return(false)
      expect(described_class.deferred?(deferred_tool)).to be false
    end
  end

  describe '.deferred_entry' do
    it 'returns name and description only' do
      entry = described_class.deferred_entry(deferred_tool)
      expect(entry).to eq({ name: 'legion.rbac_check', description: 'Check RBAC permissions.' })
    end

    it 'does not include inputSchema' do
      entry = described_class.deferred_entry(deferred_tool)
      expect(entry).not_to have_key(:inputSchema)
      expect(entry).not_to have_key(:input_schema)
    end
  end

  describe '.full_entry' do
    it 'returns the full tool hash via to_h' do
      entry = described_class.full_entry(always_loaded_tool)
      expect(entry).to be_a(Hash)
      expect(entry[:name]).to eq('legion.run_task')
    end
  end

  describe '.build_tools_list' do
    it 'returns full entries for always-loaded tools' do
      result = described_class.build_tools_list([always_loaded_tool])
      expect(result.first).to have_key(:inputSchema)
    end

    it 'returns deferred entries for non-always-loaded tools' do
      result = described_class.build_tools_list([deferred_tool])
      expect(result.first).not_to have_key(:inputSchema)
      expect(result.first).to eq({ name: 'legion.rbac_check', description: 'Check RBAC permissions.' })
    end

    it 'returns all full entries when deferred loading is disabled' do
      allow(Legion::Settings).to receive(:dig).with(:mcp, :deferred_loading, :enabled).and_return(false)
      result = described_class.build_tools_list([always_loaded_tool, deferred_tool])
      result.each { |entry| expect(entry).to have_key(:inputSchema) }
    end
  end

  describe '.resolve_schemas' do
    let(:tools) { [always_loaded_tool, deferred_tool] }

    it 'returns full schemas for matching tool names' do
      schemas = described_class.resolve_schemas(['legion.rbac_check'], tools)
      expect(schemas.length).to eq(1)
      expect(schemas.first[:name]).to eq('legion.rbac_check')
      expect(schemas.first).to have_key(:inputSchema)
    end

    it 'returns empty array for non-matching names' do
      schemas = described_class.resolve_schemas(['legion.nonexistent'], tools)
      expect(schemas).to be_empty
    end

    it 'returns multiple schemas for multiple names' do
      schemas = described_class.resolve_schemas(%w[legion.run_task legion.rbac_check], tools)
      expect(schemas.length).to eq(2)
    end
  end
end
