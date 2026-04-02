# frozen_string_literal: true

module Legion
  module MCP
    module Tools
      class CreateSchedule < ::MCP::Tool
        tool_name 'legion.create_schedule'
        description 'Create a new schedule. Requires function_id and either cron or interval.'

        input_schema(
          properties: {
            function_id: { type: 'integer', description: 'Function ID to schedule' },
            cron:        { type: 'string', description: 'Cron expression (e.g., "*/5 * * * *")' },
            interval:    { type: 'integer', description: 'Interval in seconds' },
            active:      { type: 'boolean', description: 'Whether schedule is active (default true)' },
            payload:     { type: 'object', description: 'Payload to pass to the function', additionalProperties: true }
          },
          required:   ['function_id']
        )

        class << self
          include Legion::Logging::Helper
          def call(function_id:, cron: nil, interval: nil, active: true, payload: {})
            log.info("Starting legion.mcp.tools.create_schedule.call")
            return error_response('legion-data is not connected') unless data_connected?
            return error_response('lex-scheduler is not loaded') unless scheduler_loaded?
            return error_response('cron or interval is required') if cron.nil? && interval.nil?

            attrs = {
              function_id: function_id.to_i,
              active:      active,
              payload:     Legion::JSON.dump(payload),
              last_run:    Time.at(0)
            }
            attrs[:cron] = cron if cron
            attrs[:interval] = interval.to_i if interval

            id = Legion::Extensions::Scheduler::Data::Model::Schedule.insert(attrs)
            record = Legion::Extensions::Scheduler::Data::Model::Schedule[id]
            text_response(record.values)
          rescue StandardError => e
            handle_exception(e, level: :warn, operation: "legion.mcp.tools.create_schedule.call")
            log.warn("CreateSchedule#call failed: #{e.message}")
            error_response("Failed to create schedule: #{e.message}")
          end

          private

          def data_connected?
            Legion::Settings[:data][:connected]
          rescue StandardError => e
            handle_exception(e, level: :warn, operation: "legion.mcp.tools.create_schedule.data_connected?")
            log.warn("CreateSchedule#data_connected? failed: #{e.message}")
            false
          end

          def scheduler_loaded? = defined?(Legion::Extensions::Scheduler)

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
