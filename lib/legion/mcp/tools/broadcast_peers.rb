# frozen_string_literal: true

module Legion
  module MCP
    module Tools
      class BroadcastPeers < ::MCP::Tool
        tool_name 'legion.broadcast_peers'
        description 'Broadcast a message to all mesh agents, or multicast to agents with a specific capability.'

        input_schema(
          properties: {
            message:    { type: 'string', description: 'Message content to broadcast' },
            capability: { type: 'string', description: 'If provided, multicast only to agents with this capability' }
          },
          required:   %w[message]
        )

        class << self
          include Legion::Logging::Helper

          def call(message:, capability: nil)
            log.info('Starting legion.mcp.tools.broadcast_peers.call')
            return error_response('lex-mesh is not available') unless mesh_available?

            pattern = capability ? :multicast : :broadcast
            result  = mesh_client.send_message(
              from:    'legion.mcp',
              to:      capability || :all,
              pattern: pattern,
              payload: { message: message }
            )
            text_response(result)
          rescue StandardError => e
            handle_exception(e, level: :warn, operation: 'legion.mcp.tools.broadcast_peers.call')
            log.warn("BroadcastPeers#call failed: #{e.message}")
            error_response("Failed to broadcast: #{e.message}")
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
