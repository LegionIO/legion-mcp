# frozen_string_literal: true

module Legion
  module MCP
    module Client
      module Pool
        @connections = {}
        @mutex = Mutex.new

        extend Legion::Logging::Helper

        module_function

        def connection_for(server_name)
          @mutex.synchronize do
            return @connections[server_name] if @connections.key?(server_name)

            config = ServerRegistry.servers[server_name]
            return nil unless config

            conn = Connection.new(name: server_name, **config.except(:registered_at, :source))
            @connections[server_name] = conn
          end
        end

        def all_tools
          ServerRegistry.healthy_servers.flat_map do |name, _config|
            conn = connection_for(name)
            next [] unless conn

            conn.tools.map do |tool|
              tool.merge(source: { type: :mcp, server: name })
            end
          rescue StandardError => e
            handle_exception(e, level: :warn, operation: 'legion.mcp.client.pool.all_tools')
            log.warn("MCP tool discovery failed for #{name}: #{e.message}")
            ServerRegistry.mark_unhealthy(name)
            []
          end
        end

        def reset!
          @mutex.synchronize do
            @connections.each_value do |connection|
              connection.disconnect
            rescue StandardError => e
              handle_exception(e, level: :debug, operation: 'legion.mcp.client.pool.reset!')
            end
            @connections.clear
          end
        end
      end
    end
  end
end
