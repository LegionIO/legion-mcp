# frozen_string_literal: true

require_relative '../logging_support'

module Legion
  module MCP
    module Client
      class Connection # rubocop:disable Metrics/ClassLength
        include Legion::Logging::Helper

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

            LoggingSupport.info(
              'client.connect.start',
              connection: @name,
              transport:  @transport_type,
              config:     @config.slice(:url, :command)
            )
            case @transport_type
            when :stdio
              connect_stdio
            when :http, :streamable_http
              connect_http
            else
              raise ArgumentError, "Unknown transport: #{@transport_type}"
            end
            @connected = true
            LoggingSupport.info(
              'client.connect.complete',
              connection: @name,
              transport:  @transport_type
            )
          end
        rescue StandardError => e
          @connected = false
          handle_exception(e, level: :error, operation: 'legion.mcp.client.connection.connect')
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
              LoggingSupport.info(
                'client.tools.cache_hit',
                connection: @name,
                transport:  @transport_type,
                count:      @tools_cache.size
              )
              return @tools_cache
            end

            LoggingSupport.info(
              'client.tools.fetch.start',
              connection:    @name,
              transport:     @transport_type,
              force_refresh: force_refresh
            )
            @tools_cache = fetch_tools
            @tools_cached_at = Time.now
            LoggingSupport.info(
              'client.tools.fetch.complete',
              connection: @name,
              transport:  @transport_type,
              count:      @tools_cache.size
            )
            @tools_cache
          end
        end

        def call_tool(name:, arguments: {})
          connect unless connected?
          LoggingSupport.info(
            'client.tool_call.start',
            connection: @name,
            transport:  @transport_type,
            tool_name:  name,
            arguments:  LoggingSupport.summarize_params(arguments)
          )
          result = execute_tool_call(name: name, arguments: arguments)
          LoggingSupport.info(
            'client.tool_call.complete',
            connection: @name,
            transport:  @transport_type,
            tool_name:  name,
            result:     LoggingSupport.summarize_result(result)
          )
          result
        rescue StandardError => e
          handle_exception(e, level: :warn, operation: 'legion.mcp.client.connection.call_tool')
          LoggingSupport.warn(
            'client.tool_call.failed',
            connection: @name,
            transport:  @transport_type,
            tool_name:  name,
            error:      e.message
          )
          raise
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
