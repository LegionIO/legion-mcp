# frozen_string_literal: true

module Legion
  module MCP
    module Tools
      class DoAction < ::MCP::Tool
        tool_name 'legion.do'
        description 'Execute a Legion action by describing what you want to do in natural language. ' \
                    'Routes to the best matching tool automatically. Learned patterns are served ' \
                    'instantly without LLM.'

        input_schema(
          properties: {
            intent:  {
              type:        'string',
              description: 'Natural language description (e.g., "list all running tasks")'
            },
            params:  {
              type:                 'object',
              description:          'Parameters to pass to the matched tool',
              additionalProperties: true
            },
            context: {
              type:                 'object',
              description:          'Additional context (service, environment, etc.)',
              additionalProperties: true
            }
          },
          required: ['intent']
        )

        class << self
          def call(intent:, params: {}, context: {})
            # Try Tier 0 first (learned patterns)
            tier_result = try_tier0(intent, params, context)
            if tier_result && tier_result[:tier] == 0
              return text_response(tier_result[:response].merge(
                                     _meta: { tier:       0,
                                              latency_ms: tier_result[:latency_ms],
                                              confidence: tier_result[:pattern_confidence] }
                                   ))
            end

            # Fall back to ContextCompiler tool matching (original behavior)
            matched = ContextCompiler.match_tool(intent)
            return error_response("No matching tool found for intent: #{intent}") if matched.nil?

            Legion::MCP::Observer.record_intent(intent, matched) if defined?(Legion::MCP::Observer)

            tool_params = params.transform_keys(&:to_sym)
            if tool_params.empty?
              matched.call
            else
              matched.call(**tool_params)
            end
          rescue StandardError => e
            error_response("Failed: #{e.message}")
          end

          private

          def try_tier0(intent, params, context)
            return nil unless defined?(Legion::MCP::TierRouter)

            result = Legion::MCP::TierRouter.route(
              intent:  intent,
              params:  params.transform_keys(&:to_sym),
              context: context.transform_keys(&:to_sym)
            )
            result
          rescue StandardError
            nil
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
