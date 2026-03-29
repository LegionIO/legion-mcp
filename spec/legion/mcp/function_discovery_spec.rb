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

  describe '.should_expose_from_definition?' do
    it 'returns mcp_exposed when explicitly set to true' do
      defn = { mcp_exposed: true }
      expect(described_class.should_expose_from_definition?(defn, {}, nil, false)).to be true
    end

    it 'returns mcp_exposed when explicitly set to false' do
      defn = { mcp_exposed: false }
      expect(described_class.should_expose_from_definition?(defn, {}, true, true)).to be false
    end

    it 'falls back to legacy path when mcp_exposed is nil' do
      defn = { mcp_exposed: nil }
      expect(described_class.should_expose_from_definition?(defn, { expose: true }, nil, false)).to be true
    end

    it 'falls back to class_level when mcp_exposed is nil and func_meta has no expose' do
      defn = {}
      expect(described_class.should_expose_from_definition?(defn, {}, true, false)).to be true
    end
  end

  describe '.definition_for' do
    it 'returns nil when runner does not respond to definition_for' do
      runner = Module.new
      expect(described_class.definition_for(runner, :my_func)).to be_nil
    end

    it 'delegates to runner.definition_for when available' do
      runner = Module.new do
        def self.definition_for(name)
          { mcp_exposed: true, mcp_category: :tasks } if name == :my_func
        end
      end
      result = described_class.definition_for(runner, :my_func)
      expect(result).to eq({ mcp_exposed: true, mcp_category: :tasks })
    end

    it 'returns nil when runner.definition_for returns nil' do
      runner = Module.new do
        def self.definition_for(_name) = nil
      end
      expect(described_class.definition_for(runner, :missing)).to be_nil
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
        name:          'test.discovery_tool',
        description:   'A discovered tool',
        input_schema:  { properties: { q: { type: 'string' } } },
        runner_module: Module.new { def self.my_func(**) = { success: true } },
        function_name: :my_func
      )
      expect(klass).to be < MCP::Tool
      expect(klass.tool_name).to eq('test.discovery_tool')
    end

    it 'exposes mcp_category singleton method when provided' do
      klass = described_class.build_tool_class(
        name:          'test.category_tool',
        description:   'A tool with category',
        input_schema:  { properties: {} },
        runner_module: Module.new { def self.go(**) = {} },
        function_name: :go,
        mcp_category:  :knowledge
      )
      expect(klass.mcp_category).to eq(:knowledge)
    end

    it 'exposes mcp_tier singleton method when provided' do
      klass = described_class.build_tool_class(
        name:          'test.tier_tool',
        description:   'A tool with tier',
        input_schema:  { properties: {} },
        runner_module: Module.new { def self.go(**) = {} },
        function_name: :go,
        mcp_tier:      :medium
      )
      expect(klass.mcp_tier).to eq(:medium)
    end

    it 'returns nil mcp_category and mcp_tier when not provided' do
      klass = described_class.build_tool_class(
        name:          'test.plain_tool',
        description:   'Plain tool',
        input_schema:  { properties: {} },
        runner_module: Module.new { def self.go(**) = {} },
        function_name: :go
      )
      expect(klass.mcp_category).to be_nil
      expect(klass.mcp_tier).to be_nil
    end
  end
end
