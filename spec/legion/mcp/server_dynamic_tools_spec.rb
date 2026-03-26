# frozen_string_literal: true

require 'spec_helper'
require 'legion/mcp'
require_relative '../../support/catalog_stubs'

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

  it 'includes static tools from tool_registry in dynamic_tool_list' do
    tools = Legion::MCP::Server.dynamic_tool_list
    static_names = Legion::MCP::Server.tool_registry.map(&:tool_name)
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
