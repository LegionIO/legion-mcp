# frozen_string_literal: true

require 'digest'
require_relative 'pattern_store'
require_relative 'context_guard'

module Legion
  module MCP
    module TierRouter
      CONFIDENCE_TIER0 = 0.8
      CONFIDENCE_TIER1 = 0.6

      module_function

      def route(intent:, params: {}, context: {})
        start_time = ::Process.clock_gettime(::Process::CLOCK_MONOTONIC)
        normalized = normalize_intent(intent)
        intent_hash = Digest::SHA256.hexdigest(normalized)

        ContextGuard.record_request(intent_hash)

        pattern = PatternStore.lookup(intent_hash)
        pattern ||= try_semantic_lookup(normalized)

        return tier2_response('no matching pattern') unless pattern

        confidence = pattern[:confidence] || 0.0

        return tier2_response('low confidence') if confidence < CONFIDENCE_TIER1

        return tier1_response(pattern, 'confidence below tier 0 threshold') if confidence < CONFIDENCE_TIER0

        guard_result = ContextGuard.check(pattern, params, context)
        return tier1_response(pattern, guard_result[:reason]) unless guard_result[:passed]

        begin
          results = execute_tool_chain(pattern[:tool_chain], params)
          response = generate_response(results, pattern)
          PatternStore.record_hit(intent_hash)

          elapsed_ms = ((::Process.clock_gettime(::Process::CLOCK_MONOTONIC) - start_time) * 1000).round(2)
          {
            tier:               0,
            response:           response,
            latency_ms:         elapsed_ms,
            pattern_confidence: pattern[:confidence]
          }
        rescue StandardError => e
          PatternStore.record_miss(intent_hash)
          tier1_response(pattern, "tool chain failed: #{e.message}")
        end
      end

      def normalize_intent(intent)
        intent.to_s.strip.downcase.gsub(/\s+/, ' ')
      end

      def execute_tool_chain(tool_chain, params)
        tool_chain.map do |tool_name|
          tool_class = find_tool_class(tool_name)
          raise ArgumentError, "unknown tool: #{tool_name}" unless tool_class

          if params.empty?
            tool_class.call
          else
            tool_class.call(**params.transform_keys(&:to_sym))
          end
        end
      end

      def generate_response(results, pattern)
        template = pattern[:response_template]

        if template && transformer_available?
          begin
            client = Legion::Extensions::Transformer::Client.new
            rendered = client.transform(transformation: template, payload: { results: results })
            return rendered[:result] if rendered[:success]
          rescue StandardError
            # Fall through to raw results
          end
        end

        results.size == 1 ? results.first : results
      end

      def try_semantic_lookup(normalized_intent)
        return nil unless defined?(Legion::MCP::EmbeddingIndex) && Legion::MCP::EmbeddingIndex.populated?

        embedder = Legion::MCP::EmbeddingIndex.instance_variable_get(:@embedder)
        return nil unless embedder

        intent_vector = embedder.call(normalized_intent)
        return nil unless intent_vector

        PatternStore.lookup_semantic(intent_vector)
      rescue StandardError
        nil
      end

      def find_tool_class(tool_name)
        return nil unless defined?(Legion::MCP::Server::TOOL_CLASSES)

        Legion::MCP::Server::TOOL_CLASSES.find do |klass|
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
