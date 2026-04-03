# frozen_string_literal: true

module Legion
  module MCP
    module Tools
      class MindGrowthHealth < ::MCP::Tool
        tool_name 'legion.mind_growth_health'
        description 'Get extension fitness scores, prune candidates, and improvement candidates.'

        input_schema(properties: {})

        class << self
          include Legion::Logging::Helper

          def call
            log.info('Starting legion.mcp.tools.mind_growth_health.call')
            return error_response('lex-mind-growth is not available') unless mind_growth_available?

            result = mind_growth_client.validate_fitness(extensions: [])
            text_response(result)
          rescue StandardError => e
            handle_exception(e, level: :warn, operation: 'legion.mcp.tools.mind_growth_health.call')
            log.warn("MindGrowthHealth#call failed: #{e.message}")
            error_response("Failed to get mind growth health: #{e.message}")
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
