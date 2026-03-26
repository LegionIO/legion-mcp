# frozen_string_literal: true

require 'spec_helper'
require 'legion/mcp/server'

RSpec.describe Legion::MCP::FunctionDiscovery do
  describe '.should_expose?' do
    it 'returns true when function has expose: true' do
      func_meta = { expose: true }
      expect(described_class.should_expose?(func_meta, nil, false)).to be true
    end

    it 'returns false when function has expose: false' do
      func_meta = { expose: false }
      expect(described_class.should_expose?(func_meta, nil, true)).to be false
    end

    it 'falls back to class_level when function expose is nil' do
      func_meta = {}
      expect(described_class.should_expose?(func_meta, true, false)).to be true
    end

    it 'falls back to global when both function and class are nil' do
      func_meta = {}
      expect(described_class.should_expose?(func_meta, nil, true)).to be true
    end

    it 'returns false when all levels are nil/false' do
      func_meta = {}
      expect(described_class.should_expose?(func_meta, nil, false)).to be false
    end
  end

  describe '.derive_tool_name' do
    it 'uses mcp_tool_prefix when available' do
      expect(described_class.derive_tool_name(:my_func, 'legion.codegen')).to eq('legion.codegen.my_func')
    end

    it 'uses legion.generated prefix when no prefix given' do
      expect(described_class.derive_tool_name(:my_func, nil)).to eq('legion.generated.my_func')
    end
  end

  describe '.deps_satisfied?' do
    it 'returns true when no deps required' do
      expect(described_class.deps_satisfied?(nil)).to be true
      expect(described_class.deps_satisfied?([])).to be true
    end

    it 'returns true when all deps are defined' do
      expect(described_class.deps_satisfied?(['Legion::MCP'])).to be true
    end

    it 'returns false when a dep is missing' do
      expect(described_class.deps_satisfied?(['Legion::NonExistent::Module'])).to be false
    end
  end

  describe '.build_tool_class' do
    it 'returns a Class that inherits from MCP::Tool' do
      klass = described_class.build_tool_class(
        name: 'test.discovery_tool',
        description: 'A discovered tool',
        input_schema: { properties: { q: { type: 'string' } } },
        runner_module: Module.new { def self.my_func(**) = { success: true } },
        function_name: :my_func
      )
      expect(klass).to be < ::MCP::Tool
      expect(klass.tool_name).to eq('test.discovery_tool')
    end
  end
end
