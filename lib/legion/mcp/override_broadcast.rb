# frozen_string_literal: true

module Legion
  module MCP
    module OverrideBroadcast
      EXCHANGE = 'legion.mesh'
      ROUTING_KEY = 'override.confirmed'
      CORROBORATION_BOOST = 0.3

      extend Legion::Logging::Helper

      module_function

      def publish_confirmation(tool:, lex:, confidence:, tests:)
        return unless defined?(Legion::Transport::Messages::Dynamic)

        log.debug("[mcp][override] action=publish_confirmation tool=#{tool} lex=#{lex} confidence=#{confidence}")

        node_id = begin
          Legion::Settings.dig(:node, :id)
        rescue StandardError => e
          handle_exception(e, level: :debug, operation: 'legion.mcp.override_broadcast.publish_confirmation')
          'unknown'
        end
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
        handle_exception(e, level: :warn, operation: 'legion.mcp.override_broadcast.publish_confirmation')
        log.warn("Override broadcast failed: #{e.message}")
      end

      def receive_confirmation(tool:, lex:, confidence:, tests:, node:)
        return unless defined?(Legion::LLM::OverrideConfidence)

        log.debug("[mcp][override] action=receive_confirmation tool=#{tool} node=#{node} confidence=#{confidence}")

        existing = Legion::LLM::OverrideConfidence.lookup(tool)

        if existing
          new_confidence = (existing[:confidence] + CORROBORATION_BOOST).clamp(0.0, 1.0)
          Legion::LLM::OverrideConfidence.record(tool: tool, lex: lex, confidence: new_confidence)
        else
          Legion::LLM::OverrideConfidence.record(tool: tool, lex: lex, confidence: confidence * 0.8)
        end

        store_to_apollo(tool: tool, lex: lex, confidence: confidence, tests: tests, node: node)
      rescue StandardError => e
        handle_exception(e, level: :warn, operation: 'legion.mcp.override_broadcast.receive_confirmation')
        log.warn("Override receive failed: #{e.message}")
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
        handle_exception(e, level: :warn, operation: 'legion.mcp.override_broadcast.store_to_apollo')
        log.warn("OverrideBroadcast#store_to_apollo failed: #{e.message}")
        nil
      end

      private_class_method :store_to_apollo
    end
  end
end
