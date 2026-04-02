# frozen_string_literal: true

require 'securerandom'
require_relative 'pattern_schema'

module Legion
  module MCP
    module PatternGossip
      EXCHANGE_NAME = 'tbi.patterns'
      ANNOUNCE_TTL = 86_400

      extend Legion::Logging::Helper
      module_function

      def announce(pattern)
        log.info("Starting legion.mcp.pattern_gossip.announce")
        return nil unless transport_available?

        exported = PatternSchema.export(pattern)
        message = {
          action:     'announce',
          pattern_id: exported[:pattern_id],
          pattern:    exported,
          origin:     { instance_id: instance_id },
          ttl:        ANNOUNCE_TTL,
          version:    1
        }

        Legion::Transport::Messages::Dynamic.new(
          function: "#{EXCHANGE_NAME}.announce",
          data:     message
        ).publish

        { published: true, pattern_id: exported[:pattern_id] }
      rescue StandardError => e
        handle_exception(e, level: :warn, operation: "legion.mcp.pattern_gossip.announce")
        log.warn("PatternGossip#announce failed: #{e.message}")
        nil
      end

      def receive(message)
        log.info("Starting legion.mcp.pattern_gossip.receive")
        return nil unless message.is_a?(Hash) && message[:pattern]

        PatternSchema.import(message[:pattern], trust_level: :org)
      rescue StandardError => e
        handle_exception(e, level: :warn, operation: "legion.mcp.pattern_gossip.receive")
        log.warn("PatternGossip#receive failed: #{e.message}")
        nil
      end

      def transport_available?
        defined?(Legion::Transport) &&
          Legion::Transport.respond_to?(:connected?) &&
          Legion::Transport.connected?
      end

      def instance_id
        @instance_id ||= SecureRandom.uuid
      end

      def reset!
        @instance_id = nil
      end
    end
  end
end
