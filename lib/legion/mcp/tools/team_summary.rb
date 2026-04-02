# frozen_string_literal: true

module Legion
  module MCP
    module Tools
      class TeamSummary < ::MCP::Tool
        tool_name 'legion.team_summary'
        description 'Get a summary of all digital workers for a team, including lifecycle state breakdown.'

        input_schema(
          properties: {
            team: { type: 'string', description: 'Team name to summarize' }
          },
          required:   ['team']
        )

        class << self
          include Legion::Logging::Helper
          def call(team:)
            log.info("Starting legion.mcp.tools.team_summary.call")
            return error_response('legion-data is not connected') unless data_connected?

            workers = Legion::DigitalWorker.by_team(team: team).all
            breakdown = workers.each_with_object(Hash.new(0)) { |w, counts| counts[w.values[:lifecycle_state]] += 1 }

            text_response({
                            team:             team,
                            total:            workers.size,
                            lifecycle_states: breakdown,
                            workers:          workers.map do |w|
                              w.values.slice(:worker_id, :name, :lifecycle_state, :owner_msid, :business_role)
                            end
                          })
          rescue StandardError => e
            handle_exception(e, level: :warn, operation: "legion.mcp.tools.team_summary.call")
            log.warn("TeamSummary#call failed: #{e.message}")
            error_response("Failed to fetch team summary: #{e.message}")
          end

          private

          def data_connected?
            Legion::Settings[:data][:connected]
          rescue StandardError => e
            handle_exception(e, level: :warn, operation: "legion.mcp.tools.team_summary.data_connected?")
            log.warn("TeamSummary#data_connected? failed: #{e.message}")
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
