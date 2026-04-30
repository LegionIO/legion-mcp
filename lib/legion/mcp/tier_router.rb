# frozen_string_literal: true

require 'digest'
require_relative 'pattern_store'
require_relative 'context_guard'
require_relative 'logging_support'

module Legion
  module MCP
    module TierRouter
      CONFIDENCE_TIER0 = 0.8
      CONFIDENCE_TIER1 = 0.6

      extend Legion::Logging::Helper

      module_function

      def route(intent:, params: {}, context: {}) # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/MethodLength, Metrics/PerceivedComplexity
        start_time = ::Process.clock_gettime(::Process::CLOCK_MONOTONIC)
        normalized = normalize_intent(intent)
        intent_hash = Digest::SHA256.hexdigest(normalized)
        request_id = LoggingSupport.request_id_from(context, params) || "route_#{intent_hash[0, 8]}"

        LoggingSupport.info(
          'tier_router.start',
          request_id:   request_id,
          intent_hash:  intent_hash[0, 12],
          intent:       LoggingSupport.summarize_text(intent),
          params:       LoggingSupport.summarize_params(params),
          context_keys: context.respond_to?(:keys) ? context.keys.map(&:to_s) : []
        )

        ContextGuard.record_request(intent_hash)

        pattern = PatternStore.lookup(intent_hash, request_id: request_id)
        lookup_source = :exact

        unless pattern
          pattern = try_semantic_lookup(normalized, request_id: request_id)
          lookup_source = pattern ? :semantic : :miss
        end

        LoggingSupport.info(
          'tier_router.lookup',
          request_id: request_id,
          source:     lookup_source,
          confidence: pattern&.dig(:confidence)&.round(3),
          tool_chain: Array(pattern&.dig(:tool_chain))
        )

        unless pattern
          LoggingSupport.info('tier_router.decision', request_id: request_id, tier: 2, reason: 'no matching pattern')
          return tier2_response('no matching pattern')
        end

        # After semantic lookup, track against the matched pattern's hash, not the incoming intent hash
        matched_hash = pattern[:intent_hash] || intent_hash
        confidence = pattern[:confidence] || 0.0

        if confidence < CONFIDENCE_TIER1
          LoggingSupport.info(
            'tier_router.decision',
            request_id: request_id,
            tier:       2,
            reason:     'low confidence',
            confidence: confidence.round(3),
            tool_chain: Array(pattern[:tool_chain])
          )
          return tier2_response('low confidence')
        end

        if confidence < CONFIDENCE_TIER0
          LoggingSupport.info(
            'tier_router.decision',
            request_id: request_id,
            tier:       1,
            reason:     'confidence below tier 0 threshold',
            confidence: confidence.round(3),
            tool_chain: Array(pattern[:tool_chain])
          )
          return tier1_response(pattern, 'confidence below tier 0 threshold')
        end

        guard_result = ContextGuard.check(pattern, params, context)
        LoggingSupport.info(
          'tier_router.guard',
          request_id: request_id,
          passed:     guard_result[:passed],
          reason:     guard_result[:reason]
        )
        unless guard_result[:passed]
          LoggingSupport.info(
            'tier_router.decision',
            request_id: request_id,
            tier:       1,
            reason:     guard_result[:reason],
            confidence: confidence.round(3)
          )
          return tier1_response(pattern, guard_result[:reason])
        end

        begin
          LoggingSupport.info(
            'tier_router.execute',
            request_id: request_id,
            tool_chain: Array(pattern[:tool_chain]),
            params:     LoggingSupport.summarize_params(params)
          )

          results = execute_tool_chain(pattern[:tool_chain], params, request_id: request_id)
          response = generate_response(results, pattern)
          PatternStore.record_hit(matched_hash, request_id: request_id)
          PatternStore.learn_response_template(matched_hash, results.first, request_id: request_id) if results.size == 1

          elapsed_ms = ((::Process.clock_gettime(::Process::CLOCK_MONOTONIC) - start_time) * 1000).round(2)
          LoggingSupport.info(
            'tier_router.complete',
            request_id: request_id,
            tier:       0,
            latency_ms: elapsed_ms,
            confidence: pattern[:confidence]&.round(3),
            response:   LoggingSupport.summarize_result(response)
          )
          {
            tier:               0,
            response:           response,
            latency_ms:         elapsed_ms,
            pattern_confidence: pattern[:confidence]
          }
        rescue StandardError => e
          handle_exception(e, level: :warn, operation: 'legion.mcp.tier_router.route')
          LoggingSupport.warn(
            'tier_router.execute.failed',
            request_id: request_id,
            error:      e.message,
            tool_chain: Array(pattern[:tool_chain])
          )
          PatternStore.record_miss(matched_hash, request_id: request_id)
          tier1_response(pattern, "tool chain failed: #{e.message}")
        end
      end

      def normalize_intent(intent)
        intent.to_s.strip.downcase.gsub(/\s+/, ' ')
      end

      def execute_tool_chain(tool_chain, params, request_id: nil) # rubocop:disable Metrics/MethodLength
        tool_chain.map do |tool_name| # rubocop:disable Metrics/BlockLength
          tool_class = find_tool_class(tool_name)
          raise ArgumentError, "unknown tool: #{tool_name}" unless tool_class

          LoggingSupport.info(
            'tier_router.tool_call.start',
            request_id: request_id,
            tool_name:  tool_name,
            params:     LoggingSupport.summarize_params(params)
          )

          result = if params.empty?
                     tool_class.call
                   else
                     tool_class.call(**params.transform_keys(&:to_sym))
                   end

          LoggingSupport.info(
            'tier_router.tool_call.complete',
            request_id: request_id,
            tool_name:  tool_name,
            result:     LoggingSupport.summarize_result(result)
          )

          result
        rescue StandardError => e
          handle_exception(e, level: :warn, operation: 'legion.mcp.tier_router.execute_tool_chain')
          LoggingSupport.warn(
            'tier_router.tool_call.failed',
            request_id: request_id,
            tool_name:  tool_name,
            error:      e.message
          )
          raise
        end
      end

      def generate_response(results, pattern)
        template = pattern[:response_template]

        if template && transformer_available?
          begin
            client = Legion::Extensions::Transformer::Client.new
            rendered = client.transform(transformation: template, payload: { results: results })
            return rendered[:result] if rendered[:success]
          rescue StandardError => e
            handle_exception(e, level: :debug, operation: 'legion.mcp.tier_router.generate_response')
            log.debug("TierRouter#generate_response transformer failed: #{e.message}")
          end
        end

        results.size == 1 ? results.first : results
      end

      def try_semantic_lookup(normalized_intent, request_id: nil)
        return nil unless defined?(Legion::MCP::EmbeddingIndex) && Legion::MCP::EmbeddingIndex.populated?

        embedder = Legion::MCP::EmbeddingIndex.instance_variable_get(:@embedder)
        return nil unless embedder

        intent_vector = embedder.call(normalized_intent)
        return nil unless intent_vector

        PatternStore.lookup_semantic(intent_vector, request_id: request_id)
      rescue StandardError => e
        handle_exception(e, level: :debug, operation: 'legion.mcp.tier_router.try_semantic_lookup')
        LoggingSupport.debug('tier_router.semantic_lookup.failed', request_id: request_id, error: e.message)
        nil
      end

      def find_tool_class(tool_name)
        return nil unless defined?(Legion::MCP::Server)

        Legion::MCP::Server.tool_registry.find do |klass|
          klass.respond_to?(:tool_name) && klass.tool_name == tool_name
        end
      end

      def transformer_available?
        defined?(Legion::Extensions::Transformer::Client)
      end

      def tier1_response(pattern, reason)
        { tier: 1, response: nil, pattern: pattern, reason: reason }
      end

      def tier2_response(reason)
        { tier: 2, response: nil, reason: reason }
      end
    end
  end
end
