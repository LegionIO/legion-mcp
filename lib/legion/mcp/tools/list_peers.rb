# frozen_string_literal: true

module Legion
  module MCP
    module Tools
      class ListPeers < ::MCP::Tool
        tool_name 'legion.list_peers'
        description 'List all registered mesh agents, optionally filtered by capability.'

        input_schema(
          properties: {
            capability: { type: 'string', description: 'Filter agents by capability' }
          }
        )

        class << self
          include Legion::Logging::Helper

          def call(capability: nil)
            log.info('Starting legion.mcp.tools.list_peers.call')
            return error_response('lex-mesh is not available') unless mesh_available?

            result = mesh_client.find_agents(capability: capability)
            text_response(result)
          rescue StandardError => e
            handle_exception(e, level: :warn, operation: 'legion.mcp.tools.list_peers.call')
            log.warn("ListPeers#call failed: #{e.message}")
            error_response("Failed to list peers: #{e.message}")
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
