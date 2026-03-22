# frozen_string_literal: true

module Legion
  module MCP
    module Tools
      class AskPeer < ::MCP::Tool
        tool_name 'legion.ask_peer'
        description 'Send a synchronous query to a specific mesh peer and return the result.'

        input_schema(
          properties: {
            to:      { type: 'string', description: 'Agent ID or capability name to route to' },
            query:   { type: 'string', description: 'The question or request to send to the peer' },
            timeout: { type: 'integer', description: 'Seconds to wait for response (default 30)' }
          },
          required:   %w[to query]
        )

        class << self
          def call(to:, query:, timeout: 30)
            return error_response('lex-mesh is not available') unless mesh_available?

            result = mesh_client.request_task(
              from:    'legion.mcp',
              to:      to,
              task:    'query',
              payload: { query: query },
              timeout: timeout
            )
            text_response(result)
          rescue StandardError => e
            error_response("Failed to query peer: #{e.message}")
          end

          private

          def mesh_available?
            defined?(Legion::Extensions::Mesh::Client)
          end

          def mesh_client
            @mesh_client ||= Legion::Extensions::Mesh::Client.new
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
