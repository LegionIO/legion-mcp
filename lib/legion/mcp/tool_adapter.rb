# frozen_string_literal: true

module Legion
  module MCP
    class ToolAdapter < ::MCP::Tool
      extend Legion::Logging::Helper

      class << self
        MCP_NAME_PATTERN = /[^a-zA-Z0-9_-]/

        def sanitize_tool_name(name)
          name.to_s.gsub(MCP_NAME_PATTERN, '_').slice(0, 64)
        end

        def from_legion_tool(tool_class)
          safe_name = sanitize_tool_name(tool_class.tool_name)
          log.debug("[mcp][adapter] action=from_legion_tool tool=#{safe_name}")
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
          dispatch = entry[:dispatch_type]
          log.debug("[mcp][adapter] action=from_registry_entry name=#{entry[:name]} " \
                    "dispatch_type=#{dispatch} has_class=#{!tool_class.nil?}")
          return from_legion_tool(tool_class) if tool_class.is_a?(Class) && tool_class.respond_to?(:tool_name)

          build_from_metadata(entry)
        end

        private

        def dispatch_tool_class(klass, name, args)
          if klass.respond_to?(:call)
            klass.call(**args)
          elsif klass.respond_to?(:new)
            instance = klass.new
            return { error: "Tool #{name} instance does not implement call" } unless instance.respond_to?(:call)

            dispatch_tool_instance(instance, name, args)
          else
            { error: "Tool #{name} has no executable class" }
          end
        end

        def dispatch_tool_instance(instance, _name, args)
          call_method = instance.method(:call)
          return instance.call if call_method.arity.zero? && args.empty?

          if keyword_callable_method?(call_method)
            begin
              instance.call(**args)
            rescue ArgumentError
              instance.call(args)
            end
          else
            instance.call(args)
          end
        end

        def keyword_callable_method?(call_method)
          call_method.parameters.any? { |type, _name| %i[key keyreq keyrest].include?(type) }
        end

        def result_to_response(result)
          if result.is_a?(Hash) && result[:content]
            content = result[:content].map { |c| { type: c[:type] || 'text', text: c[:text] || '' } }
            ::MCP::Tool::Response.new(content, error: result[:error] || false)
          else
            error = result.is_a?(Hash) ? !result[:error].nil? : false
            text = result.is_a?(String) ? result : Legion::JSON.dump(result)
            ::MCP::Tool::Response.new([{ type: 'text', text: text }], error: error)
          end
        end

        def build_from_metadata(entry)
          entry_name   = sanitize_tool_name(entry[:name])
          log.debug("[mcp][adapter] action=build_from_metadata tool=#{entry_name} " \
                    "dispatch_type=#{entry[:dispatch_type]}")
          entry_desc   = entry[:description] || ''
          entry_schema = entry[:input_schema].is_a?(Hash) ? entry[:input_schema] : { properties: {} }
          entry_ref    = entry
          adapter      = self

          Class.new(::MCP::Tool) do
            tool_name entry_name
            description entry_desc
            input_schema(entry_schema)

            define_singleton_method(:legion_tool_entry) { entry_ref }

            define_singleton_method(:call) do |**args|
              result = if entry_ref[:dispatch_type] == :mcp_remote
                         server_name = entry_ref[:mcp_server] || entry_ref[:extension]&.sub(/\Amcp:/, '')
                         conn = Legion::MCP::Client::Pool.connection_for(server_name)
                         raise "MCP server #{server_name} not available" unless conn

                         conn.call_tool(name: entry_ref[:name], arguments: args)
                       else
                         adapter.send(:dispatch_tool_class, entry_ref[:tool_class], entry_ref[:name], args)
                       end
              adapter.send(:result_to_response, result)
            rescue StandardError => e
              ::MCP::Tool::Response.new([{ type: 'text', text: Legion::JSON.dump({ error: e.message }) }], error: true)
            end
          end
        end
      end
    end
  end
end
