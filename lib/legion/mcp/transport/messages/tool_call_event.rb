# frozen_string_literal: true

module Legion
  module MCP
    module Transport
      module Messages
        class ToolCallEvent < Legion::Transport::Message
          def exchange
            Exchanges::Audit
          end

          def routing_key
            @options[:routing_key] || 'mcp.audit.tool_call'
          end

          def type
            'mcp_audit'
          end
        end
      end
    end
  end
end
