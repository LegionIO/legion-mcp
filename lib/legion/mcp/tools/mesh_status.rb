# frozen_string_literal: true

module Legion
  module MCP
    module Tools
      class MeshStatus < ::MCP::Tool
        tool_name 'legion.mesh_status'
        description 'Get current mesh network status including registered agents and topology.'

        input_schema(properties: {})

        class << self
          def call
            return error_response('lex-mesh is not available') unless mesh_available?

            result = mesh_client.mesh_status
            text_response(result)
          rescue StandardError => e
            Legion::Logging.warn("MeshStatus#call failed: #{e.message}") if defined?(Legion::Logging)
            error_response("Failed to get mesh status: #{e.message}")
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
