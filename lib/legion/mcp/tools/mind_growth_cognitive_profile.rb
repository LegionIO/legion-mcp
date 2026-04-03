# frozen_string_literal: true

module Legion
  module MCP
    module Tools
      class MindGrowthCognitiveProfile < ::MCP::Tool
        tool_name 'legion.mind_growth_cognitive_profile'
        description 'Analyze the current cognitive architecture coverage against reference models.'

        input_schema(properties: {})

        class << self
          include Legion::Logging::Helper

          def call
            log.info('Starting legion.mcp.tools.mind_growth_cognitive_profile.call')
            return error_response('lex-mind-growth is not available') unless mind_growth_available?

            result = mind_growth_client.cognitive_profile
            text_response(result)
          rescue StandardError => e
            handle_exception(e, level: :warn, operation: 'legion.mcp.tools.mind_growth_cognitive_profile.call')
            log.warn("MindGrowthCognitiveProfile#call failed: #{e.message}")
            error_response("Failed to get cognitive profile: #{e.message}")
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
