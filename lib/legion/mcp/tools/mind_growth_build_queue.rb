# frozen_string_literal: true

module Legion
  module MCP
    module Tools
      class MindGrowthBuildQueue < ::MCP::Tool
        tool_name 'legion.mind_growth_build_queue'
        description 'List the current build queue of approved mind growth proposals.'

        input_schema(properties: {})

        class << self
          include Legion::Logging::Helper

          def call
            log.info('Starting legion.mcp.tools.mind_growth_build_queue.call')
            return error_response('lex-mind-growth is not available') unless mind_growth_available?

            result = mind_growth_client.list_proposals(status: :approved)
            text_response(result)
          rescue StandardError => e
            handle_exception(e, level: :warn, operation: 'legion.mcp.tools.mind_growth_build_queue.call')
            log.warn("MindGrowthBuildQueue#call failed: #{e.message}")
            error_response("Failed to get build queue: #{e.message}")
          end

          private

          def mind_growth_available?
            defined?(Legion::Extensions::MindGrowth::Client)
          end

          def mind_growth_client
            @mind_growth_client ||= Legion::Extensions::MindGrowth::Client.new
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
