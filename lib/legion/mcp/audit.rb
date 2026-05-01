# frozen_string_literal: true

module Legion
  module MCP
    module Audit
      extend Legion::Logging::Helper

      ROUTING_KEYS = {
        tool_call:   'mcp.audit.tool_call',
        client_call: 'mcp.audit.client_call',
        governance:  'mcp.audit.governance'
      }.freeze

      module_function

      def emit_tool_call(**event)
        publish(ROUTING_KEYS[:tool_call], event, :ToolCallEvent)
      end

      def emit_client_call(**event)
        publish(ROUTING_KEYS[:client_call], event, :ClientCallEvent)
      end

      def emit_governance(**event)
        publish(ROUTING_KEYS[:governance], event, :GovernanceEvent)
      end

      def transport_available?
        !!(defined?(Legion::Transport::Message) &&
           defined?(Legion::MCP::Transport::Exchanges::Audit))
      end

      def transport_connected?
        Legion::Settings.dig(:transport, :connected) == true
      rescue StandardError => e
        handle_exception(e, level: :debug, handled: true, operation: 'mcp.audit.transport_connected?')
        false
      end

      def publish(routing_key, event, message_sym)
        return unless transport_available? && transport_connected?

        message_class = Legion::MCP::Transport::Messages.const_get(message_sym)
        message_class.new(routing_key: routing_key, **event).publish
      rescue StandardError => e
        handle_exception(e, level: :warn, handled: true, operation: 'mcp.audit.publish')
      end
    end
  end
end
