# frozen_string_literal: true

require 'spec_helper'
require 'legion/mcp'

# Stub Capability and Catalog::Registry for tests
module Legion
  module Extensions
    Capability = ::Data.define(
      :name, :extension, :runner, :function,
      :description, :parameters, :tags, :loaded_at
    ) do
      def self.from_runner(extension:, runner:, function:, description: nil, parameters: nil, tags: nil)
        canonical = "#{extension}:#{runner.to_s.gsub(/([A-Z])/, '_\1').sub(/^_/, '').downcase}:#{function}"
        new(
          name: canonical, extension: extension, runner: runner.to_s,
          function: function.to_s, description: description,
          parameters: parameters || {}, tags: Array(tags), loaded_at: Time.now
        )
      end

      def to_mcp_tool
        snake_runner = runner.gsub(/([A-Z])/, '_\1').sub(/^_/, '').downcase
        tool_name = "legion.#{extension.delete_prefix('lex-').tr('-', '_')}.#{snake_runner}.#{function}"
        properties = (parameters || {}).transform_values do |v|
          v.is_a?(Hash) ? v : { type: v.to_s }
        end
        {
          name: tool_name,
          description: description || "#{extension} #{runner}##{function}",
          input_schema: {
            type: 'object', properties: properties,
            required: parameters&.select { |_, v| v.is_a?(Hash) && v[:required] }&.keys&.map(&:to_s) || []
          }
        }
      end
    end unless defined?(Legion::Extensions::Capability)

    module Catalog
      module Registry
        @capabilities = []
        @by_name = {}
        @mutex = Mutex.new

        module_function

        def register(capability)
          @mutex.synchronize do
            return if @by_name.key?(capability.name)

            @capabilities << capability
            @by_name[capability.name] = capability
          end
        end

        def unregister(name)
          @mutex.synchronize do
            cap = @by_name.delete(name)
            @capabilities.delete(cap) if cap
          end
        end

        def for_mcp
          @mutex.synchronize { @capabilities.dup }
        end

        def reset!
          @mutex.synchronize do
            @capabilities.clear
            @by_name.clear
          end
        end
      end
    end
  end
end

RSpec.describe 'MCP Server dynamic tool list' do
  before do
    allow(Legion::Settings).to receive(:dig).and_return(nil)
    Legion::Extensions::Catalog::Registry.reset!
  end

  it 'includes Catalog capabilities in dynamic_tool_list' do
    cap = Legion::Extensions::Capability.from_runner(
      extension: 'lex-jira', runner: 'Issue', function: 'create',
      description: 'Create a Jira issue',
      parameters: { summary: { type: 'string', required: true } }
    )
    Legion::Extensions::Catalog::Registry.register(cap)

    tools = Legion::MCP::Server.dynamic_tool_list
    tool_names = tools.map { |t| t[:name] }
    expect(tool_names).to include('legion.jira.issue.create')
  end

  it 'includes static TOOL_CLASSES in dynamic_tool_list' do
    tools = Legion::MCP::Server.dynamic_tool_list
    static_names = Legion::MCP::Server::TOOL_CLASSES.map(&:tool_name)
    tool_names = tools.map { |t| t[:name] }
    static_names.each { |sn| expect(tool_names).to include(sn) }
  end

  it 'removes tools when extension is unloaded' do
    cap = Legion::Extensions::Capability.from_runner(
      extension: 'lex-jira', runner: 'Issue', function: 'create',
      description: 'Create a Jira issue'
    )
    Legion::Extensions::Catalog::Registry.register(cap)
    Legion::Extensions::Catalog::Registry.unregister(cap.name)

    tools = Legion::MCP::Server.dynamic_tool_list
    tool_names = tools.map { |t| t[:name] }
    expect(tool_names).not_to include('legion.jira.issue.create')
  end
end
