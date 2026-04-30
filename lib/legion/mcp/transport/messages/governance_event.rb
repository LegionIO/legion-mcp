# frozen_string_literal: true

module Legion
  module MCP
    module Transport
      module Messages
        class GovernanceEvent < Legion::Transport::Message
          def exchange
            Exchanges::Audit
          end

          def routing_key
            @options[:routing_key] || 'mcp.audit.governance'
          end

          def type
            'mcp_audit'
          end
        end
      end
    end
  end
end
