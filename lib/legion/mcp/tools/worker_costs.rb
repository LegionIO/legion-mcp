# frozen_string_literal: true

module Legion
  module MCP
    module Tools
      class WorkerCosts < ::MCP::Tool
        tool_name 'legion.worker_costs'
        description 'Retrieve cost data for a digital worker. Returns a stub response until lex-metering is available.'

        input_schema(
          properties: {
            worker_id: { type: 'string', description: 'UUID of the digital worker' },
            period:    { type: 'string', description: 'Reporting period: daily, weekly, monthly (default: weekly)' }
          },
          required:   ['worker_id']
        )

        class << self
          include Legion::Logging::Helper
          def call(worker_id:, period: 'weekly')
            log.info("Starting legion.mcp.tools.worker_costs.call")
            return error_response('legion-data is not connected') unless data_connected?

            worker = Legion::DigitalWorker.find(worker_id: worker_id)
            return error_response("Worker not found: #{worker_id}") unless worker

            text_response({
                            worker_id:   worker_id,
                            period:      period,
                            available:   false,
                            message:     'Cost metering is not yet available. Install lex-metering to enable worker cost tracking.',
                            worker_name: worker.values[:name]
                          })
          rescue StandardError => e
            handle_exception(e, level: :warn, operation: "legion.mcp.tools.worker_costs.call")
            log.warn("WorkerCosts#call failed: #{e.message}")
            error_response("Failed to fetch worker costs: #{e.message}")
          end

          private

          def data_connected?
            Legion::Settings[:data][:connected]
          rescue StandardError => e
            handle_exception(e, level: :warn, operation: "legion.mcp.tools.worker_costs.data_connected?")
            log.warn("WorkerCosts#data_connected? failed: #{e.message}")
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
