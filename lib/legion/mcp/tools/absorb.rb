# frozen_string_literal: true

module Legion
  module MCP
    module Tools
      class Absorb < ::MCP::Tool
        tool_name 'legion.absorb'
        description 'Absorb content from a URL or resource into the knowledge system. ' \
                    'Dispatches to the registered absorber that matches the input pattern.'

        input_schema(
          properties: {
            input: { type: 'string', description: 'URL, file path, or resource identifier to absorb' },
            scope: { type: 'string', enum: %w[local global all],
                     description: 'Knowledge scope (default: global)' }
          },
          required:   %w[input]
        )

        class << self
          include Legion::Logging::Helper

          def call(input:, scope: 'global')
            log.info('Starting legion.mcp.tools.absorb.call')
            return error_response('AbsorberDispatch not available') unless dispatch_available?

            scope_str = scope.to_s
            allowed_scopes = { 'local' => :local, 'global' => :global, 'all' => :all }
            return error_response("invalid scope: #{scope}") unless allowed_scopes.key?(scope_str)

            result = Legion::Extensions::Actors::AbsorberDispatch.dispatch(
              input:   input,
              context: { scope: allowed_scopes[scope_str] }
            )

            if result[:success]
              text_response(result)
            else
              error_response(result[:error] || 'absorption failed')
            end
          rescue StandardError => e
            handle_exception(e, level: :warn, operation: 'legion.mcp.tools.absorb.call')
            log.warn("Absorb MCP tool failed: #{e.message}")
            error_response("Absorption failed: #{e.message}")
          end

          private

          def dispatch_available?
            defined?(Legion::Extensions::Actors::AbsorberDispatch)
          end

          def text_response(data)
            ::MCP::Tool::Response.new([{ type: 'text', text: Legion::JSON.dump(data) }])
          end

          def error_response(msg)
            ::MCP::Tool::Response.new([{ type: 'text', text: Legion::JSON.dump({ error: msg }) }], error: true)
          end
        end
      end
    end
  end
end
