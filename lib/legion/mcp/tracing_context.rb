# frozen_string_literal: true

require 'securerandom'

module Legion
  module MCP
    module TracingContext
      THREAD_KEYS = %i[
        legion_mcp_conversation_id
        legion_mcp_request_id
        legion_mcp_exchange_id
        legion_mcp_tool_call_id
        legion_mcp_trace_id
      ].freeze

      module_function

      def generate_conversation_id
        "mcp_#{SecureRandom.uuid}"
      end

      def generate_trace_id
        SecureRandom.hex(16)
      end

      def generate_request_id(jsonrpc_id)
        "req_#{jsonrpc_id || SecureRandom.hex(8)}"
      end

      def generate_exchange_id
        "exch_#{SecureRandom.hex(12)}"
      end

      def generate_tool_call_id
        "call_#{SecureRandom.hex(12)}"
      end

      def set(conversation_id:, request_id:, exchange_id:, tool_call_id:, trace_id:)
        Thread.current[:legion_mcp_conversation_id] = conversation_id
        Thread.current[:legion_mcp_request_id] = request_id
        Thread.current[:legion_mcp_exchange_id] = exchange_id
        Thread.current[:legion_mcp_tool_call_id] = tool_call_id
        Thread.current[:legion_mcp_trace_id] = trace_id
      end

      def clear
        THREAD_KEYS.each { |key| Thread.current[key] = nil }
      end

      def current
        THREAD_KEYS.each_with_object({}) do |key, hash|
          short = key.to_s.delete_prefix('legion_mcp_').to_sym
          hash[short] = Thread.current[key]
        end
      end
    end
  end
end
