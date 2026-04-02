# frozen_string_literal: true

module Legion
  module MCP
    module Tools
      class MindGrowthPropose < ::MCP::Tool
        tool_name 'legion.mind_growth_propose'
        description 'Propose a new cognitive extension concept for the architecture.'

        input_schema(
          properties: {
            category:    { type:        'string',
                           description: 'Cognitive category (cognition, perception, introspection, ' \
                                        'safety, communication, memory, motivation, coordination)' },
            description: { type: 'string', description: 'Description of the proposed extension' },
            name:        { type: 'string', description: 'Optional extension name' }
          }
        )

        class << self
          include Legion::Logging::Helper
          def call(params = {})
            log.info("Starting legion.mcp.tools.mind_growth_propose.call")
            return error_response('lex-mind-growth is not available') unless mind_growth_available?

            result = mind_growth_client.propose_concept(
              category:    params[:category]&.to_sym,
              description: params[:description],
              name:        params[:name]
            )
            text_response(result)
          rescue StandardError => e
            handle_exception(e, level: :warn, operation: "legion.mcp.tools.mind_growth_propose.call")
            log.warn("MindGrowthPropose#call failed: #{e.message}")
            error_response("Failed to propose concept: #{e.message}")
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
