# frozen_string_literal: true

require 'spec_helper'
require 'legion/mcp/settings'

RSpec.describe Legion::MCP::Settings do
  it 'preserves configured deferral when registering library defaults again' do
    Legion::Settings[:mcp][:deferred_loading][:enabled] = false

    load File.expand_path('../../../lib/legion/mcp/settings.rb', __dir__)

    tool = Class.new(MCP::Tool) do
      tool_name 'settings.configured'
      description 'Configured tool'
      input_schema(properties: {})
    end
    expect(Legion::MCP::DeferredRegistry.build_tools_list([tool]).first).to have_key(:inputSchema)
  end
end
