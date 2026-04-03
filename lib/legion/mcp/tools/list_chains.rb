# frozen_string_literal: true

module Legion
  module MCP
    module Tools
      class ListChains < ::MCP::Tool
        tool_name 'legion.list_chains'
        description 'List all task chains.'

        input_schema(
          properties: {
            limit: { type: 'integer', description: 'Max results (default 25, max 100)' }
          }
        )

        class << self
          include Legion::Logging::Helper

          def call(limit: 25)
            log.info('Starting legion.mcp.tools.list_chains.call')
            return error_response('legion-data is not connected') unless data_connected?
            return error_response('chain data model is not available') unless chain_model?

            limit = limit.to_i.clamp(1, 100)
            text_response(Legion::Data::Model::Chain.order(:id).limit(limit).all.map(&:values))
          rescue StandardError => e
            handle_exception(e, level: :warn, operation: 'legion.mcp.tools.list_chains.call')
            log.warn("ListChains#call failed: #{e.message}")
            error_response("Failed to list chains: #{e.message}")
          end

          private

          def data_connected?
            Legion::Settings[:data][:connected]
          rescue StandardError => e
            handle_exception(e, level: :warn, operation: 'legion.mcp.tools.list_chains.data_connected?')
            log.warn("ListChains#data_connected? failed: #{e.message}")
            false
          end

          def chain_model? = Legion::Data::Model.const_defined?(:Chain)

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
