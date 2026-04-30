# frozen_string_literal: true

module Legion
  module MCP
    module Tools
      class CreateChain < ::MCP::Tool
        tool_name 'legion.create_chain'
        description 'Create a new task chain.'

        input_schema(
          properties: {
            name: { type: 'string', description: 'Chain name' }
          },
          required:   ['name']
        )

        class << self
          include Legion::Logging::Helper

          def call(name:, **attrs)
            log.info('Starting legion.mcp.tools.create_chain.call')
            return error_response('legion-data is not connected') unless data_connected?
            return error_response('chain data model is not available') unless chain_model?

            id = Legion::Data::Model::Chain.insert(attrs.merge(name: name))
            record = Legion::Data::Model::Chain[id]
            text_response(record.values)
          rescue StandardError => e
            handle_exception(e, level: :warn, operation: 'legion.mcp.tools.create_chain.call')
            error_response("Failed to create chain: #{e.message}")
          end

          private

          def data_connected?
            Legion::Settings[:data][:connected]
          rescue StandardError => e
            handle_exception(e, level: :warn, operation: 'legion.mcp.tools.create_chain.data_connected?')
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
