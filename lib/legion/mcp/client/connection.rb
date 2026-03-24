# frozen_string_literal: true

module Legion
  module MCP
    module Client
      class Connection
        attr_reader :name, :transport_type, :config

        TOOL_CACHE_TTL = 300 # seconds

        def initialize(name:, transport:, **config)
          @name = name
          @transport_type = transport.to_sym
          @config = config
          @tools_cache = nil
          @tools_cached_at = nil
          @connected = false
          @mutex = Mutex.new
        end

        def connected?
          @connected
        end

        def connect
          @mutex.synchronize do
            return if @connected

            case @transport_type
            when :stdio
              connect_stdio
            when :http, :streamable_http
              connect_http
            else
              raise ArgumentError, "Unknown transport: #{@transport_type}"
            end
            @connected = true
          end
        rescue StandardError
          @connected = false
          raise
        end

        def disconnect
          @mutex.synchronize do
            @transport&.close if @transport.respond_to?(:close)
            @connected = false
            @tools_cache = nil
          end
        end

        def tools(force_refresh: false)
          @mutex.synchronize do
            if !force_refresh && @tools_cache && @tools_cached_at &&
               (Time.now - @tools_cached_at) < TOOL_CACHE_TTL
              return @tools_cache
            end

            @tools_cache = fetch_tools
            @tools_cached_at = Time.now
            @tools_cache
          end
        end

        def call_tool(name:, arguments: {})
          connect unless connected?
          execute_tool_call(name: name, arguments: arguments)
        end

        private

        def connect_stdio
          @transport = { type: :stdio, command: @config[:command], pid: nil }
        end

        def connect_http
          @transport = { type: :http, url: @config[:url], auth: @config[:auth] }
        end

        def fetch_tools
          connect unless connected?
          []
        end

        def execute_tool_call(_name:, _arguments:)
          connect unless connected?
          { content: [], error: false }
        end
      end
    end
  end
end
