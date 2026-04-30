# frozen_string_literal: true

module Legion
  module MCP
    module Tools
      class StateDiff < ::MCP::Tool
        tool_name 'legion.state_diff'
        description 'Return only changed system state since a given timestamp. Token-efficient polling ' \
                    'for agents monitoring system state without re-fetching everything.'

        input_schema(
          properties: {
            since:    {
              type:        'string',
              description: 'ISO 8601 timestamp to diff against (e.g., "2026-03-31T12:00:00Z")'
            },
            snapshot: {
              type:        'boolean',
              description: 'When true, takes a state snapshot and returns it (use before polling with since:)'
            }
          }
        )

        class << self
          include Legion::Logging::Helper

          def call(since: nil, snapshot: nil)
            log.info('Starting legion.mcp.tools.state_diff.call')
            if snapshot
              result = StateTracker.snapshot
              text_response(result)
            elsif since
              result = StateTracker.diff(since: since)
              text_response(result)
            else
              text_response(StateTracker.collect_state.merge(timestamp: Time.now.iso8601))
            end
          rescue StandardError => e
            handle_exception(e, level: :warn, operation: 'legion.mcp.tools.state_diff.call')
            error_response("Failed: #{e.message}")
          end

          private

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
