# frozen_string_literal: true

module Legion
  module MCP
    module Settings
      module_function

      def defaults
        {
          servers: {},
          overrides: {},
          tool_cache_ttl: 300,
          connect_timeout: 10,
          call_timeout: 30
        }
      end
    end
  end
end
