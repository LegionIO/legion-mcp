# frozen_string_literal: true

module Legion
  module MCP
    module Tools
      class DeleteRelationship < ::MCP::Tool
        tool_name 'legion.delete_relationship'
        description 'Delete a relationship by ID.'

        input_schema(
          properties: {
            id: { type: 'integer', description: 'Relationship ID' }
          },
          required:   ['id']
        )

        class << self
          include Legion::Logging::Helper

          def call(id:)
            log.info('Starting legion.mcp.tools.delete_relationship.call')
            return error_response('legion-data is not connected') unless data_connected?
            return error_response('relationship data model is not available') unless relationship_model?

            record = Legion::Data::Model::Relationship[id.to_i]
            return error_response("Relationship #{id} not found") unless record

            record.delete
            text_response({ deleted: true, id: id })
          rescue StandardError => e
            handle_exception(e, level: :warn, operation: 'legion.mcp.tools.delete_relationship.call')
            error_response("Failed to delete relationship: #{e.message}")
          end

          private

          def data_connected?
            Legion::Settings[:data][:connected]
          rescue StandardError => e
            handle_exception(e, level: :warn, operation: 'legion.mcp.tools.delete_relationship.data_connected?')
            false
          end

          def relationship_model? = Legion::Data::Model.const_defined?(:Relationship, false)

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
