# frozen_string_literal: true

module Legion
  module MCP
    module Tools
      class GetStatus < ::MCP::Tool
        tool_name 'legion.get_status'
        description 'Get Legion service health status and component info.'

        input_schema(properties: {})

        class << self
          def call
            status = {
              version:    Legion::VERSION,
              ready:      begin
                Legion::Readiness.ready?
              rescue StandardError => e
                Legion::Logging.debug("GetStatus#call Readiness.ready? failed: #{e.message}") if defined?(Legion::Logging)
                false
              end,
              components: begin
                Legion::Readiness.to_h
              rescue StandardError => e
                Legion::Logging.debug("GetStatus#call Readiness.to_h failed: #{e.message}") if defined?(Legion::Logging)
                {}
              end,
              node:       begin
                Legion::Settings[:client][:name]
              rescue StandardError => e
                Legion::Logging.debug("GetStatus#call Settings[:client][:name] failed: #{e.message}") if defined?(Legion::Logging)
                'unknown'
              end
            }
            text_response(status)
          rescue StandardError => e
            Legion::Logging.warn("GetStatus#call failed: #{e.message}") if defined?(Legion::Logging)
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
