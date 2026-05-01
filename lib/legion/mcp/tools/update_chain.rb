# frozen_string_literal: true

module Legion
  module MCP
    module Tools
      class UpdateChain < ::MCP::Tool
        tool_name 'legion.update_chain'
        description 'Update an existing task chain.'

        input_schema(
          properties: {
            id:   { type: 'integer', description: 'Chain ID' },
            name: { type: 'string', description: 'New chain name' }
          },
          required:   ['id']
        )

        class << self
          include Legion::Logging::Helper

          def call(id:, **attrs)
            log.info('Starting legion.mcp.tools.update_chain.call')
            return error_response('legion-data is not connected') unless data_connected?
            return error_response('chain data model is not available') unless chain_model?

            record = Legion::Data::Model::Chain[id.to_i]
            return error_response("Chain #{id} not found") unless record

            record.update(attrs) unless attrs.empty?
            record.refresh
            text_response(record.values)
          rescue StandardError => e
            handle_exception(e, level: :warn, operation: 'legion.mcp.tools.update_chain.call')
            error_response("Failed to update chain: #{e.message}")
          end

          private

          def data_connected?
            Legion::Settings[:data][:connected]
          rescue StandardError => e
            handle_exception(e, level: :warn, operation: 'legion.mcp.tools.update_chain.data_connected?')
            false
          end

          def chain_model? = Legion::Data::Model.const_defined?(:Chain, false)

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
