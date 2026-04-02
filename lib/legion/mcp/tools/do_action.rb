# frozen_string_literal: true

require 'securerandom'
require_relative '../logging_support'

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
          include Legion::Logging::Helper
          def call(intent:, params: {}, context: {}) # rubocop:disable Metrics/CyclomaticComplexity
            request_id = LoggingSupport.request_id_from(context, params) || "mcp_#{SecureRandom.hex(6)}"
            normalized_context = symbolize_hash(context).merge(request_id: request_id)
            tool_params = params.transform_keys(&:to_sym)

            LoggingSupport.info(
              'do_action.start',
              request_id:   request_id,
              intent:       LoggingSupport.summarize_text(intent),
              params:       LoggingSupport.summarize_params(tool_params),
              context_keys: normalized_context.keys.map(&:to_s)
            )

            tier_result = try_tier0(intent, tool_params, normalized_context, request_id: request_id)

            if tier_result
              LoggingSupport.info(
                'do_action.tier_result',
                request_id: request_id,
                tier:       tier_result[:tier],
                reason:     tier_result[:reason],
                confidence: tier_result[:pattern_confidence] || tier_result.dig(:pattern, :confidence),
                tool_chain: Array(tier_result.dig(:pattern, :tool_chain))
              )
            else
              LoggingSupport.info('do_action.tier_result', request_id: request_id, tier: 'none', reason: 'tier router unavailable')
            end

            case tier_result&.dig(:tier)
            when 0
              response = text_response(tier_result[:response].merge(
                                     _meta: { tier:       0,
                                              latency_ms: tier_result[:latency_ms],
                                              confidence: tier_result[:pattern_confidence] }
                                   ))
              LoggingSupport.info(
                'do_action.complete',
                request_id: request_id,
                path:       'tier0',
                result:     LoggingSupport.summarize_result(response),
                matched:    Array(tier_result.dig(:pattern, :tool_chain))
              )
              return response
            when 1
              llm_result = try_tier1(intent, tier_result[:pattern], request_id: request_id)
              if llm_result
                response = text_response({ result: llm_result,
                                           _meta:  { tier: 1, pattern_hint: tier_result[:pattern][:intent_text] } })
                LoggingSupport.info(
                  'do_action.complete',
                  request_id: request_id,
                  path:       'tier1',
                  matched:    Array(tier_result.dig(:pattern, :tool_chain)),
                  result:     LoggingSupport.summarize_result(response)
                )
                return response
              end
            when 2
              llm_result = try_tier2(intent, request_id: request_id)
              if llm_result
                response = text_response({ result: llm_result, _meta: { tier: 2 } })
                LoggingSupport.info(
                  'do_action.complete',
                  request_id: request_id,
                  path:       'tier2',
                  result:     LoggingSupport.summarize_result(response)
                )
                return response
              end
            end

            # Fall back to ContextCompiler tool matching
            matched = ContextCompiler.match_tool(intent)
            if matched.nil?
              LoggingSupport.warn(
                'do_action.no_match',
                request_id: request_id,
                intent:     LoggingSupport.summarize_text(intent)
              )
              return error_response("No matching tool found for intent: #{intent}")
            end

            matched_name = matched.respond_to?(:tool_name) ? matched.tool_name : matched.to_s
            LoggingSupport.info(
              'do_action.match',
              request_id:   request_id,
              matched_tool: matched_name,
              params:       LoggingSupport.summarize_params(tool_params)
            )

            result = tool_params.empty? ? matched.call : matched.call(**tool_params)
            LoggingSupport.info(
              'do_action.complete',
              request_id: request_id,
              path:       'context_compiler',
              matched:    matched_name,
              result:     LoggingSupport.summarize_result(result)
            )

            record_feedback(intent, matched_name, success: true)
            result
          rescue StandardError => e
            handle_exception(e, level: :warn, operation: "legion.mcp.tools.do_action.call")
            LoggingSupport.warn(
              'do_action.failed',
              request_id: defined?(request_id) ? request_id : nil,
              matched:    defined?(matched_name) ? matched_name : nil,
              error:      e.message
            )
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

          def try_tier1(intent, pattern, request_id: nil)
            return nil unless defined?(Legion::LLM) && Legion::LLM.started?

            hint = "Known pattern: #{pattern[:intent_text]}. Tools: #{Array(pattern[:tool_chain]).join(', ')}. "
            LoggingSupport.info(
              'do_action.tier1.start',
              request_id: request_id,
              pattern:    pattern[:intent_text],
              tool_chain: Array(pattern[:tool_chain])
            )
            result = Legion::LLM.ask(
              "#{hint}User intent: #{intent}",
              caller: { extension: 'legion-mcp', tool: 'do_action', tier: 1, request_id: request_id }
            )
            LoggingSupport.info(
              'do_action.tier1.complete',
              request_id: request_id,
              result:     LoggingSupport.summarize_result(result)
            )
            result
          rescue StandardError => e
            handle_exception(e, level: :debug, operation: "legion.mcp.tools.do_action.try_tier1")
            LoggingSupport.debug('do_action.tier1.failed', request_id: request_id, error: e.message)
            nil
          end

          def try_tier2(intent, request_id: nil)
            return nil unless defined?(Legion::LLM) && Legion::LLM.started?

            catalog = ContextCompiler.respond_to?(:compressed_catalog) ? ContextCompiler.compressed_catalog : []
            context_str = catalog.any? ? "Available tools: #{Legion::JSON.dump(catalog)}. " : ''
            LoggingSupport.info(
              'do_action.tier2.start',
              request_id: request_id,
              catalog:    LoggingSupport.summarize_array(catalog)
            )
            result = Legion::LLM.ask(
              "#{context_str}User intent: #{intent}",
              caller: { extension: 'legion-mcp', tool: 'do_action', tier: 2, request_id: request_id }
            )
            LoggingSupport.info(
              'do_action.tier2.complete',
              request_id: request_id,
              result:     LoggingSupport.summarize_result(result)
            )
            result
          rescue StandardError => e
            handle_exception(e, level: :debug, operation: "legion.mcp.tools.do_action.try_tier2")
            LoggingSupport.debug('do_action.tier2.failed', request_id: request_id, error: e.message)
            nil
          end

          def try_tier0(intent, params, context, request_id: nil)
            return nil unless defined?(Legion::MCP::TierRouter)

            Legion::MCP::TierRouter.route(
              intent:  intent,
              params:  params.transform_keys(&:to_sym),
              context: symbolize_hash(context).merge(request_id: request_id)
            )
          rescue StandardError => e
            handle_exception(e, level: :debug, operation: "legion.mcp.tools.do_action.try_tier0")
            LoggingSupport.debug('do_action.tier0.failed', request_id: request_id, error: e.message)
            nil
          end

          def text_response(data)
            ::MCP::Tool::Response.new([{ type: 'text', text: Legion::JSON.dump(data) }])
          end

          def error_response(msg)
            ::MCP::Tool::Response.new([{ type: 'text', text: Legion::JSON.dump({ error: msg }) }], error: true)
          end

          def symbolize_hash(hash)
            hash.to_h.transform_keys(&:to_sym)
          end
        end
      end
    end
  end
end
