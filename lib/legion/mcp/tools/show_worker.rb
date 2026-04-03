# frozen_string_literal: true

module Legion
  module MCP
    module Tools
      class ShowWorker < ::MCP::Tool
        tool_name 'legion.show_worker'
        description 'Get full details for a single digital worker by ID.'

        input_schema(
          properties: {
            worker_id: { type: 'string', description: 'UUID of the digital worker' }
          },
          required:   ['worker_id']
        )

        class << self
          include Legion::Logging::Helper

          def call(worker_id:)
            log.info('Starting legion.mcp.tools.show_worker.call')
            return error_response('legion-data is not connected') unless data_connected?

            worker = Legion::DigitalWorker.find(worker_id: worker_id)
            return error_response("Worker not found: #{worker_id}") unless worker

            text_response(worker.values)
          rescue StandardError => e
            handle_exception(e, level: :warn, operation: 'legion.mcp.tools.show_worker.call')
            log.warn("ShowWorker#call failed: #{e.message}")
            error_response("Failed to fetch worker: #{e.message}")
          end

          private

          def data_connected?
            Legion::Settings[:data][:connected]
          rescue StandardError => e
            handle_exception(e, level: :warn, operation: 'legion.mcp.tools.show_worker.data_connected?')
            log.warn("ShowWorker#data_connected? failed: #{e.message}")
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
