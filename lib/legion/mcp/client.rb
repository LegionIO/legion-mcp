# frozen_string_literal: true

module Legion
  module MCP
    module Client
      extend Legion::Logging::Helper

      module_function

      def boot
        log.info('Starting legion.mcp.client.boot')
        servers = begin
          Legion::Settings.dig(:mcp, :servers)
        rescue StandardError => e
          handle_exception(e, level: :debug, operation: 'legion.mcp.client.boot')
          nil
        end
        return unless servers.is_a?(Hash) && servers.any?

        ServerRegistry.load_from_settings(servers)
        log.info("MCP Client: #{servers.length} servers registered")
      end

      def shutdown
        Pool.reset!
        ServerRegistry.reset!
      end

      def register(name, **config)
        ServerRegistry.register(name, **config)
      end

      def deregister(name)
        Pool.reset!
        ServerRegistry.deregister(name)
      end
    end
  end
end

require_relative 'client/server_registry'
require_relative 'client/connection'
require_relative 'client/pool'
