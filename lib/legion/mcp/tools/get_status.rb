# frozen_string_literal: true

module Legion
  module MCP
    module Tools
      class GetStatus < ::MCP::Tool
        tool_name 'legion.get_status'
        description 'Get Legion service health status and component info.'

        input_schema(properties: {})

        class << self
          include Legion::Logging::Helper
          def call
            log.info("Starting legion.mcp.tools.get_status.call")
            status = {
              version:    Legion::VERSION,
              ready:      begin
                Legion::Readiness.ready?
              rescue StandardError => e
                handle_exception(e, level: :debug, operation: "legion.mcp.tools.get_status.call")
                log.debug("GetStatus#call Readiness.ready? failed: #{e.message}")
                false
              end,
              components: begin
                Legion::Readiness.to_h
              rescue StandardError => e
                handle_exception(e, level: :debug, operation: "legion.mcp.tools.get_status.call")
                log.debug("GetStatus#call Readiness.to_h failed: #{e.message}")
                {}
              end,
              node:       begin
                Legion::Settings[:client][:name]
              rescue StandardError => e
                handle_exception(e, level: :debug, operation: "legion.mcp.tools.get_status.call")
                log.debug("GetStatus#call Settings[:client][:name] failed: #{e.message}")
                'unknown'
              end
            }
            text_response(status)
          rescue StandardError => e
            handle_exception(e, level: :warn, operation: "legion.mcp.tools.get_status.call")
            log.warn("GetStatus#call failed: #{e.message}")
            error_response("Failed to get status: #{e.message}")
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
