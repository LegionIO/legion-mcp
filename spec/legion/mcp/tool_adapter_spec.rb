# frozen_string_literal: true

require 'spec_helper'
require 'legion/mcp/tool_adapter'

RSpec.describe Legion::MCP::ToolAdapter do
  describe '.sanitize_tool_name' do
    it 'replaces invalid characters with underscores' do
      expect(described_class.sanitize_tool_name('legion.my.tool')).to eq('legion_my_tool')
    end

    it 'truncates to 64 characters' do
      long_name = 'a' * 100
      expect(described_class.sanitize_tool_name(long_name).length).to eq(64)
    end
  end

  describe '.from_legion_tool' do
    let(:tool_class) do
      Class.new do
        def self.tool_name
          'legion.test_adapter'
        end

        def self.description
          'A test tool for adapter'
        end

        def self.input_schema
          { properties: { q: { type: 'string' } } }
        end

        def self.call(**_args)
          { result: 'ok' }
        end
      end
    end

    it 'returns a class inheriting from MCP::Tool' do
      adapted = described_class.from_legion_tool(tool_class)
      expect(adapted).to be < MCP::Tool
    end

    it 'preserves the tool name (sanitized)' do
      adapted = described_class.from_legion_tool(tool_class)
      expect(adapted.tool_name).to eq('legion_test_adapter')
    end

    it 'preserves the description' do
      adapted = described_class.from_legion_tool(tool_class)
      expect(adapted.description).to eq('A test tool for adapter')
    end

    it 'exposes the original tool class via legion_tool_class' do
      adapted = described_class.from_legion_tool(tool_class)
      expect(adapted.legion_tool_class).to eq(tool_class)
    end

    it 'delegates call to the tool class' do
      adapted = described_class.from_legion_tool(tool_class)
      response = adapted.call
      expect(response).to be_a(MCP::Tool::Response)
    end
  end

  describe '.from_registry_entry' do
    context 'with a loaded tool class' do
      let(:tool_class) do
        Class.new do
          def self.tool_name
            'legion.registry_loaded'
          end

          def self.description
            'Loaded tool class'
          end

          def self.input_schema
            { properties: {} }
          end

          def self.call(**_args)
            { loaded: true }
          end
        end
      end

      it 'delegates to from_legion_tool when tool_class is a Class with tool_name' do
        entry = { name: 'legion.registry_loaded', tool_class: tool_class }
        adapted = described_class.from_registry_entry(entry)
        expect(adapted.legion_tool_class).to eq(tool_class)
      end
    end

    context 'with metadata only (no tool class)' do
      let(:entry) do
        {
          name:         'legion.metadata_tool',
          description:  'A metadata-only tool',
          input_schema: { properties: { query: { type: 'string' } } },
          tool_class:   nil
        }
      end

      it 'builds an MCP tool from metadata' do
        adapted = described_class.from_registry_entry(entry)
        expect(adapted).to be < MCP::Tool
        expect(adapted.tool_name).to eq('legion_metadata_tool')
      end

      it 'preserves the description' do
        adapted = described_class.from_registry_entry(entry)
        expect(adapted.description).to eq('A metadata-only tool')
      end

      it 'exposes the original entry via legion_tool_entry' do
        adapted = described_class.from_registry_entry(entry)
        expect(adapted.legion_tool_entry).to eq(entry)
      end

      it 'returns an error response when tool_class is nil' do
        adapted = described_class.from_registry_entry(entry)
        response = adapted.call
        expect(response).to be_a(MCP::Tool::Response)
        expect(response.error?).to be true
      end
    end

    context 'with a class-level callable tool_class' do
      let(:callable_class) do
        Class.new do
          def self.call(**_args)
            { class_called: true }
          end
        end
      end

      let(:entry) do
        {
          name:         'legion.callable_tool',
          description:  'Callable via .call',
          input_schema: { properties: {} },
          tool_class:   callable_class
        }
      end

      it 'dispatches through tool_class.call' do
        adapted = described_class.from_registry_entry(entry)
        response = adapted.call
        expect(response).to be_a(MCP::Tool::Response)
        expect(response.error?).to be false
      end
    end

    context 'with an instance-level callable tool_class' do
      let(:instance_class) do
        Class.new do
          def call(_args)
            { instance_called: true }
          end
        end
      end

      let(:entry) do
        {
          name:         'legion.instance_tool',
          description:  'Callable via .new.call',
          input_schema: { properties: {} },
          tool_class:   instance_class
        }
      end

      it 'dispatches through tool_class.new.call' do
        adapted = described_class.from_registry_entry(entry)
        response = adapted.call
        expect(response).to be_a(MCP::Tool::Response)
        expect(response.error?).to be false
      end
    end

    context 'with missing input_schema' do
      let(:entry) do
        {
          name:        'legion.no_schema_tool',
          description: 'No schema provided',
          tool_class:  nil
        }
      end

      it 'defaults input_schema to empty properties' do
        adapted = described_class.from_registry_entry(entry)
        expect(adapted).to be < MCP::Tool
        expect(adapted.tool_name).to eq('legion_no_schema_tool')
      end
    end
  end
end
