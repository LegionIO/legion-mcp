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
            if @connections.key?(server_name)
              log.debug("[mcp][pool] action=connection_for server=#{server_name} cached=true")
              return @connections[server_name]
            end

            config = ServerRegistry.servers[server_name]
            unless config
              log.debug("[mcp][pool] action=connection_for server=#{server_name} found=false")
              return nil
            end

            log.debug("[mcp][pool] action=connection_for server=#{server_name} creating=true")
            conn = Connection.new(name: server_name, **config.except(:registered_at, :source))
            @connections[server_name] = conn
          end
        end

        def all_tools
          healthy = ServerRegistry.healthy_servers
          log.debug("[mcp][pool] action=all_tools healthy_servers=#{healthy.size}")
          healthy.flat_map do |name, _config|
            conn = connection_for(name)
            next [] unless conn

            conn.tools.map do |tool|
              tool_entry = {
                name:          tool[:name],
                description:   tool[:description],
                input_schema:  tool[:input_schema],
                tool_class:    nil,
                dispatch_type: :mcp_remote,
                extension:     "mcp:#{name}",
                source:        :mcp_remote,
                mcp_server:    name
              }
              # Register into the central registry so LLM pipeline sees these too
              if defined?(Legion::Settings::Extensions) && Legion::Settings::Extensions.respond_to?(:register_tool)
                Legion::Settings::Extensions.register_tool(tool[:name], tool_entry)
              end
              tool_entry
            end
          rescue StandardError => e
            handle_exception(e, level: :warn, operation: 'legion.mcp.client.pool.all_tools')
            ServerRegistry.mark_unhealthy(name)
            []
          end
        end

        def refresh_tools!
          log.debug("[mcp][pool] action=refresh_tools connections=#{@connections.size}")
          @mutex.synchronize do
            @connections.each_value do |conn|
              conn.tools(force_refresh: true)
            rescue StandardError => e
              handle_exception(e, level: :debug, operation: 'legion.mcp.client.pool.refresh_tools!')
            end
          end
          all_tools
        end

        def reset!
          log.debug("[mcp][pool] action=reset connections=#{@connections.size}")
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
