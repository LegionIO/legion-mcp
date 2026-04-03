# frozen_string_literal: true

module Legion
  module MCP
    module Tools
      class NotifyPeer < ::MCP::Tool
        tool_name 'legion.notify_peer'
        description 'Send a fire-and-forget async notification to a specific mesh agent.'

        input_schema(
          properties: {
            to:      { type: 'string', description: 'Target agent ID' },
            message: { type: 'string', description: 'Notification content to send' }
          },
          required:   %w[to message]
        )

        class << self
          include Legion::Logging::Helper

          def call(to:, message:)
            log.info('Starting legion.mcp.tools.notify_peer.call')
            return error_response('lex-mesh is not available') unless mesh_available?

            result = mesh_client.send_message(
              from:    'legion.mcp',
              to:      to,
              pattern: :unicast,
              payload: { message: message }
            )
            text_response(result)
          rescue StandardError => e
            handle_exception(e, level: :warn, operation: 'legion.mcp.tools.notify_peer.call')
            log.warn("NotifyPeer#call failed: #{e.message}")
            error_response("Failed to notify peer: #{e.message}")
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
