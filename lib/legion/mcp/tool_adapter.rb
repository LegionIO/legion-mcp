# frozen_string_literal: true

module Legion
  module MCP
    class ToolAdapter < ::MCP::Tool
      class << self
        def from_legion_tool(tool_class)
          Class.new(::MCP::Tool) do
            tool_name tool_class.tool_name
            description tool_class.description
            input_schema(tool_class.input_schema || { properties: {} })

            define_singleton_method(:legion_tool_class) { tool_class }

            define_singleton_method(:call) do |**params|
              result = tool_class.call(**params)
              if result.is_a?(Hash) && result[:content]
                content = result[:content].map do |c|
                  { type: c[:type] || 'text', text: c[:text] || '' }
                end
                ::MCP::Tool::Response.new(content, error: result[:error] || false)
              else
                text = result.is_a?(String) ? result : Legion::JSON.dump(result)
                error = result.is_a?(Hash) ? !!result[:error] : false
                ::MCP::Tool::Response.new([{ type: 'text', text: text }], error: error)
              end
            rescue StandardError => e
              ::MCP::Tool::Response.new([{ type: 'text', text: Legion::JSON.dump({ error: e.message }) }], error: true)
            end
          end
        end
      end
    end
  end
end
