# frozen_string_literal: true

module Legion
  module MCP
    module Client
      module_function

      def boot
        servers = Legion::Settings.dig(:mcp, :servers) rescue nil # rubocop:disable Style/RescueModifier
        return unless servers.is_a?(Hash) && servers.any?

        ServerRegistry.load_from_settings(servers)
        Legion::Logging.info("MCP Client: #{servers.length} servers registered") if defined?(Legion::Logging)
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
