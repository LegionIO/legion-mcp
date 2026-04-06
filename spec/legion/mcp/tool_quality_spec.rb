# frozen_string_literal: true

require 'spec_helper'
require 'legion/mcp'

RSpec.describe Legion::MCP::ToolQuality do
  before do
    allow(Legion::Settings).to receive(:dig).and_return(nil)
  end

  describe '.audit_tool' do
    let(:good_tool) do
      Class.new(MCP::Tool) do
        tool_name 'legion.good_tool'
        description 'A well-described tool that does useful things for the system.'
        input_schema(properties: { query: { type: 'string', description: 'The search query to execute' } })
      end
    end

    let(:bad_tool) do
      Class.new(MCP::Tool) do
        tool_name 'legion.bad_tool'
        description 'Short.'
        input_schema(properties: { x: { type: 'string' } })
      end
    end

    it 'passes a well-described tool' do
      result = described_class.audit_tool(good_tool)
      expect(result[:quality]).to eq(:pass)
      expect(result[:issues]).to be_empty
    end

    it 'warns on short description' do
      result = described_class.audit_tool(bad_tool)
      expect(result[:quality]).to eq(:warn)
      expect(result[:issues].any? { |i| i.include?('description too short') }).to be true
    end

    it 'warns on missing param description' do
      result = described_class.audit_tool(bad_tool)
      expect(result[:issues].any? { |i| i.include?("param 'x'") }).to be true
    end
  end

  describe '.resolve_category' do
    let(:tasks_tool) do
      Class.new(MCP::Tool) do
        tool_name 'legion.run_task'
        description 'Execute a task.'
        input_schema(properties: {})
      end
    end

    let(:mesh_tool) do
      Class.new(MCP::Tool) do
        tool_name 'legion.ask_peer'
        description 'Ask a peer.'
        input_schema(properties: {})
      end
    end

    let(:unknown_tool) do
      Class.new(MCP::Tool) do
        tool_name 'legion.unknown_xyz'
        description 'Unknown tool.'
        input_schema(properties: {})
      end
    end

    it 'resolves tasks category from CATEGORIES' do
      expect(described_class.resolve_category(tasks_tool)).to eq(:tasks)
    end

    it 'resolves mesh category from EXPANDED_CATEGORIES' do
      expect(described_class.resolve_category(mesh_tool)).to eq(:mesh)
    end

    it 'returns uncategorized for unknown tools' do
      expect(described_class.resolve_category(unknown_tool)).to eq(:uncategorized)
    end

    it 'prefers mcp_category when defined' do
      categorized = Class.new(MCP::Tool) do
        tool_name 'legion.custom'
        description 'Custom tool.'
        input_schema(properties: {})
        define_singleton_method(:mcp_category) { 'custom_cat' }
      end
      expect(described_class.resolve_category(categorized)).to eq(:custom_cat)
    end
  end

  describe '.capability_matrix' do
    it 'returns entries for all registered tools' do
      matrix = described_class.capability_matrix
      expect(matrix).to be_an(Array)
      expect(matrix.length).to eq(Legion::MCP::Server.tool_registry.size)
    end

    it 'includes reads and writes flags for each entry' do
      matrix = described_class.capability_matrix
      expect(matrix).to all(include(:reads, :writes))
    end

    it 'marks tools with list_ prefix as readers' do
      list_tool = Class.new(MCP::Tool) do
        tool_name 'legion.list_things'
        description 'List all the things.'
        input_schema(properties: {})
      end
      allow(Legion::MCP::Server).to receive(:tool_registry).and_return([list_tool])
      matrix = described_class.capability_matrix
      entry = matrix.find { |e| e[:name] == 'legion.list_things' }
      expect(entry[:reads]).to be true
    end

    it 'marks tools with create_ prefix as writers' do
      create_tool = Class.new(MCP::Tool) do
        tool_name 'legion.create_thing'
        description 'Create a thing.'
        input_schema(properties: {})
      end
      allow(Legion::MCP::Server).to receive(:tool_registry).and_return([create_tool])
      matrix = described_class.capability_matrix
      entry = matrix.find { |e| e[:name] == 'legion.create_thing' }
      expect(entry[:writes]).to be true
    end
  end

  describe '.summary' do
    it 'returns total_tools, passing, warnings, and by_category' do
      result = described_class.summary
      expect(result).to have_key(:total_tools)
      expect(result).to have_key(:passing)
      expect(result).to have_key(:warnings)
      expect(result).to have_key(:by_category)
    end

    it 'total_tools matches registry size' do
      result = described_class.summary
      expect(result[:total_tools]).to eq(Legion::MCP::Server.tool_registry.size)
    end
  end
end
