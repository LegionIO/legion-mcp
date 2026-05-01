# frozen_string_literal: true

module Legion
  module MCP
    module Client
      module ServerRegistry
        extend Legion::Logging::Helper

        @servers = {}
        @health = {}
        @mutex = Mutex.new

        module_function

        def load_from_settings(settings_hash)
          log.debug("[mcp][server_registry] action=load_from_settings count=#{settings_hash.size}")
          @mutex.synchronize do
            settings_hash.each do |name, config|
              @servers[name] = config.merge(registered_at: Time.now, source: :settings)
              @health[name] = { healthy: true, last_check: Time.now }
            end
          end
        end

        def register(name, **config)
          log.debug("[mcp][server_registry] action=register server=#{name}")
          @mutex.synchronize do
            @servers[name] = config.merge(registered_at: Time.now, source: :dynamic)
            @health[name] = { healthy: true, last_check: Time.now }
          end
        end

        def deregister(name)
          log.debug("[mcp][server_registry] action=deregister server=#{name}")
          @mutex.synchronize do
            @servers.delete(name)
            @health.delete(name)
          end
        end

        def servers
          @mutex.synchronize { @servers.dup }
        end

        def healthy_servers
          @mutex.synchronize do
            @servers.select do |name, _|
              h = @health[name]
              next true if h.nil? || h[:healthy]

              cooldown = h[:cooldown] || 60
              if Time.now - (h[:marked_at] || Time.now) >= cooldown
                h[:healthy] = true
                true
              else
                false
              end
            end
          end
        end

        def mark_unhealthy(name, cooldown: 60)
          log.debug("[mcp][server_registry] action=mark_unhealthy server=#{name} cooldown=#{cooldown}")
          @mutex.synchronize do
            @health[name] = {
              healthy:    false,
              marked_at:  Time.now,
              cooldown:   cooldown,
              last_check: Time.now
            }
          end
        end

        def mark_healthy(name)
          log.debug("[mcp][server_registry] action=mark_healthy server=#{name}")
          @mutex.synchronize do
            @health[name] = { healthy: true, last_check: Time.now }
          end
        end

        def reset!
          @mutex.synchronize do
            @servers.clear
            @health.clear
          end
        end
      end
    end
  end
end
