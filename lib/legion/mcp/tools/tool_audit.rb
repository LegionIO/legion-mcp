# frozen_string_literal: true

module Legion
  module MCP
    module Tools
      class ToolAudit < ::MCP::Tool
        tool_name 'legion.tool_audit'
        description 'Audit MCP tools for quality, categorization, and capability matrix. ' \
                    'Returns issues, category assignments, and read/write capabilities.'

        input_schema(
          properties: {
            mode: {
              type:        'string',
              description: 'Audit mode: summary (default), matrix (capability matrix), issues (quality issues only)',
              enum:        %w[summary matrix issues]
            }
          }
        )

        class << self
          def call(mode: 'summary')
            result = case mode
                     when 'matrix'
                       ToolQuality.capability_matrix
                     when 'issues'
                       ToolQuality.audit_all.select { |r| r[:quality] == :warn }
                     else
                       ToolQuality.summary
                     end

            text_response(result)
          rescue StandardError => e
            Legion::Logging.warn("ToolAudit#call failed: #{e.message}") if defined?(Legion::Logging)
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
