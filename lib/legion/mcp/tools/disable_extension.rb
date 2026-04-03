# frozen_string_literal: true

module Legion
  module MCP
    module Tools
      class DisableExtension < ::MCP::Tool
        tool_name 'legion.disable_extension'
        description 'Disable a Legion extension by ID.'

        input_schema(
          properties: {
            id: { type: 'integer', description: 'Extension ID' }
          },
          required:   ['id']
        )

        class << self
          include Legion::Logging::Helper

          def call(id:)
            log.info('Starting legion.mcp.tools.disable_extension.call')
            return error_response('legion-data is not connected') unless data_connected?

            ext = Legion::Data::Model::Extension[id.to_i]
            return error_response("Extension #{id} not found") unless ext

            ext.update(active: false)
            ext.refresh
            text_response(ext.values)
          rescue StandardError => e
            handle_exception(e, level: :warn, operation: 'legion.mcp.tools.disable_extension.call')
            log.warn("DisableExtension#call failed: #{e.message}")
            error_response("Failed to disable extension: #{e.message}")
          end

          private

          def data_connected?
            Legion::Settings[:data][:connected]
          rescue StandardError => e
            handle_exception(e, level: :warn, operation: 'legion.mcp.tools.disable_extension.data_connected?')
            log.warn("DisableExtension#data_connected? failed: #{e.message}")
            false
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
