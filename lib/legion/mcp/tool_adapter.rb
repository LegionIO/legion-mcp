# frozen_string_literal: true

module Legion
  module MCP
    class ToolAdapter < ::MCP::Tool
      class << self
        MCP_NAME_PATTERN = /[^a-zA-Z0-9_-]/

        def sanitize_tool_name(name)
          name.to_s.gsub(MCP_NAME_PATTERN, '_').slice(0, 64)
        end

        def from_legion_tool(tool_class)
          safe_name = sanitize_tool_name(tool_class.tool_name)
          Class.new(::MCP::Tool) do
            tool_name safe_name
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

        # Builds an MCP tool from a Settings::Extensions registry entry hash.
        # If the entry contains a loaded tool_class, delegates to from_legion_tool.
        # Otherwise builds a thin adapter from the metadata alone.
        def from_registry_entry(entry)
          tool_class = entry[:tool_class]
          return from_legion_tool(tool_class) if tool_class.is_a?(Class) && tool_class.respond_to?(:tool_name)

          build_from_metadata(entry)
        end

        private

        def build_from_metadata(entry)
          entry_name   = sanitize_tool_name(entry[:name])
          entry_desc   = entry[:description] || ''
          entry_schema = entry[:input_schema].is_a?(Hash) ? entry[:input_schema] : { properties: {} }
          entry_ref    = entry

          Class.new(::MCP::Tool) do
            tool_name entry_name
            description entry_desc
            input_schema(entry_schema)

            define_singleton_method(:legion_tool_entry) { entry_ref }

            define_singleton_method(:call) do |**args|
              klass = entry_ref[:tool_class]
              result =
                if klass.respond_to?(:call)
                  klass.call(**args)
                elsif klass.respond_to?(:new)
                  klass.new.call(args)
                else
                  { error: "Tool #{entry_ref[:name]} has no executable class" }
                end

              error = result.is_a?(Hash) ? !!result[:error] : false
              text = result.is_a?(String) ? result : Legion::JSON.dump(result)
              ::MCP::Tool::Response.new([{ type: 'text', text: text }], error: error)
            rescue StandardError => e
              ::MCP::Tool::Response.new([{ type: 'text', text: Legion::JSON.dump({ error: e.message }) }], error: true)
            end
          end
        end
      end
    end
  end
end
