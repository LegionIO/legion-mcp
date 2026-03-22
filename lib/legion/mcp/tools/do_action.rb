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
          required:   ['intent']
        )

        class << self
          def call(intent:, params: {}, context: {}) # rubocop:disable Metrics/CyclomaticComplexity
            tier_result = try_tier0(intent, params, context)

            case tier_result&.dig(:tier)
            when 0
              return text_response(tier_result[:response].merge(
                                     _meta: { tier:       0,
                                              latency_ms: tier_result[:latency_ms],
                                              confidence: tier_result[:pattern_confidence] }
                                   ))
            when 1
              llm_result = try_tier1(intent, tier_result[:pattern])
              if llm_result
                return text_response({ result: llm_result,
                                       _meta:  { tier: 1, pattern_hint: tier_result[:pattern][:intent_text] } })
              end
            when 2
              llm_result = try_tier2(intent)
              return text_response({ result: llm_result, _meta: { tier: 2 } }) if llm_result
            end

            # Fall back to ContextCompiler tool matching
            matched = ContextCompiler.match_tool(intent)
            return error_response("No matching tool found for intent: #{intent}") if matched.nil?

            matched_name = matched.respond_to?(:tool_name) ? matched.tool_name : matched.to_s

            tool_params = params.transform_keys(&:to_sym)
            result = tool_params.empty? ? matched.call : matched.call(**tool_params)

            record_feedback(intent, matched_name, success: true)
            result
          rescue StandardError => e
            Legion::Logging.warn("DoAction#call failed: #{e.message}") if defined?(Legion::Logging)
            record_feedback(intent, matched_name, success: false) if defined?(matched_name)
            error_response("Failed: #{e.message}")
          end

          private

          def record_feedback(intent, tool_name, success:)
            return unless defined?(Legion::MCP::Observer)

            Legion::MCP::Observer.record_intent_with_result(
              intent:    intent,
              tool_name: tool_name,
              success:   success
            )
          end

          def try_tier1(intent, pattern)
            return nil unless defined?(Legion::LLM) && Legion::LLM.started?

            hint = "Known pattern: #{pattern[:intent_text]}. Tools: #{Array(pattern[:tool_chain]).join(', ')}. "
            Legion::LLM.ask("#{hint}User intent: #{intent}")
          rescue StandardError => e
            Legion::Logging.debug("DoAction#try_tier1 failed: #{e.message}") if defined?(Legion::Logging)
            nil
          end

          def try_tier2(intent)
            return nil unless defined?(Legion::LLM) && Legion::LLM.started?

            catalog = ContextCompiler.respond_to?(:compressed_catalog) ? ContextCompiler.compressed_catalog : []
            context_str = catalog.any? ? "Available tools: #{Legion::JSON.dump(catalog)}. " : ''
            Legion::LLM.ask("#{context_str}User intent: #{intent}")
          rescue StandardError => e
            Legion::Logging.debug("DoAction#try_tier2 failed: #{e.message}") if defined?(Legion::Logging)
            nil
          end

          def try_tier0(intent, params, context)
            return nil unless defined?(Legion::MCP::TierRouter)

            Legion::MCP::TierRouter.route(
              intent:  intent,
              params:  params.transform_keys(&:to_sym),
              context: context.transform_keys(&:to_sym)
            )
          rescue StandardError => e
            Legion::Logging.debug("DoAction#try_tier0 failed: #{e.message}") if defined?(Legion::Logging)
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
