# frozen_string_literal: true

require 'shellwords'
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
          @mcp_client = nil
          @mcp_transport = nil
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

            verify_connection!

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
            @mcp_transport&.close if @mcp_transport.respond_to?(:close)
            @connected = false
            @mcp_client = nil
            @mcp_transport = nil
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
          command = @config[:command]
          raise ArgumentError, 'stdio transport requires a :command config key' unless command

          parts = command.is_a?(Array) ? command : Shellwords.split(command)
          cmd = parts.shift
          @mcp_transport = ::MCP::Client::Stdio.new(command: cmd, args: parts)
          @mcp_client = ::MCP::Client.new(transport: @mcp_transport)
        end

        def connect_http
          url = @config[:url]
          raise ArgumentError, 'http transport requires a :url config key' unless url

          headers = @config[:headers] || {}
          headers['Authorization'] ||= @config[:auth] if @config[:auth]

          @mcp_transport = ::MCP::Client::HTTP.new(url: url, headers: headers)
          @mcp_client = ::MCP::Client.new(transport: @mcp_transport)
        end

        # Verify the connection by requesting the tool list. This triggers
        # the MCP initialize handshake on stdio transports and confirms the
        # HTTP endpoint is reachable. The result seeds the tools cache.
        def verify_connection!
          raw_tools = @mcp_client.tools
          @tools_cache = raw_tools.map do |tool|
            {
              name:         tool.name,
              description:  tool.description,
              input_schema: tool.input_schema
            }
          end
          @tools_cached_at = Time.now
        rescue ::MCP::Client::ServerError, ::MCP::Client::RequestHandlerError => e
          raise ConnectionError, "MCP handshake failed for #{@name}: #{e.message}"
        end

        def fetch_tools
          connect unless connected?

          raw_tools = @mcp_client.tools
          raw_tools.map do |tool|
            {
              name:         tool.name,
              description:  tool.description,
              input_schema: tool.input_schema
            }
          end
        rescue ::MCP::Client::ServerError, ::MCP::Client::RequestHandlerError => e
          raise ConnectionError, "Failed to fetch tools from #{@name}: #{e.message}"
        end

        def execute_tool_call(name:, arguments:)
          connect unless connected?

          response = @mcp_client.call_tool(name: name, arguments: arguments)
          result = response.is_a?(Hash) ? response['result'] || response : response

          content = result.is_a?(Hash) ? result['content'] || result.fetch('content', []) : []
          is_error = result.is_a?(Hash) ? result.fetch('isError', false) : false

          { content: content, error: is_error }
        rescue ::MCP::Client::ServerError => e
          { content: [{ type: 'text', text: e.message }], error: true }
        rescue ::MCP::Client::RequestHandlerError => e
          raise ConnectionError, "Tool call failed on #{@name}: #{e.message}"
        end
      end

      class ConnectionError < StandardError; end
    end
  end
end
