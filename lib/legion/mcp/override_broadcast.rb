# frozen_string_literal: true

module Legion
  module MCP
    module OverrideBroadcast
      EXCHANGE = 'legion.mesh'
      ROUTING_KEY = 'override.confirmed'
      CORROBORATION_BOOST = 0.3

      module_function

      def publish_confirmation(tool:, lex:, confidence:, tests:)
        return unless defined?(Legion::Transport::Messages::Dynamic)

        node_id = Legion::Settings.dig(:node, :id) rescue 'unknown' # rubocop:disable Style/RescueModifier
        Legion::Transport::Messages::Dynamic.new(
          function:    'override_confirmed',
          exchange:    EXCHANGE,
          routing_key: ROUTING_KEY,
          opts:        {
            tool: tool, lex: lex, confidence: confidence,
            tests: tests, node: node_id, timestamp: Time.now.iso8601
          }
        ).publish
      rescue StandardError => e
        Legion::Logging.warn("Override broadcast failed: #{e.message}") if defined?(Legion::Logging)
      end

      def receive_confirmation(tool:, lex:, confidence:, tests:, node:)
        return unless defined?(Legion::LLM::OverrideConfidence)

        existing = Legion::LLM::OverrideConfidence.lookup(tool)

        if existing
          new_confidence = (existing[:confidence] + CORROBORATION_BOOST).clamp(0.0, 1.0)
          Legion::LLM::OverrideConfidence.record(tool: tool, lex: lex, confidence: new_confidence)
        else
          Legion::LLM::OverrideConfidence.record(tool: tool, lex: lex, confidence: confidence * 0.8)
        end

        store_to_apollo(tool: tool, lex: lex, confidence: confidence, tests: tests, node: node)
      rescue StandardError => e
        Legion::Logging.warn("Override receive failed: #{e.message}") if defined?(Legion::Logging)
      end

      def store_to_apollo(tool:, lex:, confidence:, tests:, node:)
        return unless defined?(Legion::Apollo) && Legion::Apollo.started?

        Legion::Apollo.ingest(
          content:          "Override confirmed: #{tool} -> #{lex} (confidence: #{confidence}, tests: #{tests})",
          tags:             %w[override mesh_confirmed] + [tool],
          source_channel:   'mesh',
          submitted_by:     "mesh:#{node}",
          knowledge_domain: 'system'
        )
      rescue StandardError => e
        Legion::Logging.warn("OverrideBroadcast#store_to_apollo failed: #{e.message}") if defined?(Legion::Logging)
        nil
      end

      private_class_method :store_to_apollo
    end
  end
end
