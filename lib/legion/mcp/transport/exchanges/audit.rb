# frozen_string_literal: true

module Legion
  module MCP
    module Transport
      module Exchanges
        class Audit < Legion::Transport::Exchange
          def exchange_name
            'mcp.audit'
          end
        end
      end
    end
  end
end
