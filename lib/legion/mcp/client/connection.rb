# frozen_string_literal: true

require 'securerandom'
require 'shellwords'

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

            log.info("[mcp] client.connect.start #{Utils.format_fields(connection: @name, transport: @transport_type,
                                                                       config: @config.slice(:url, :command))}")
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
            log.info("[mcp] client.connect.complete #{Utils.format_fields(connection: @name, transport: @transport_type)}")
          end
        rescue StandardError => e
          @connected = false
          handle_exception(e, level: :error, operation: 'legion.mcp.client.connection.connect')
          raise
        end

        def disconnect
          log.debug("[mcp][client] action=disconnect connection=#{@name}")
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
              log.info("[mcp] client.tools.cache_hit #{Utils.format_fields(connection: @name, transport: @transport_type,
                                                                           count: @tools_cache.size)}")
              return @tools_cache
            end

            log.info("[mcp] client.tools.fetch.start #{Utils.format_fields(connection: @name, transport: @transport_type,
                                                                           force_refresh: force_refresh)}")
            @tools_cache = fetch_tools
            @tools_cached_at = Time.now
            log.info("[mcp] client.tools.fetch.complete #{Utils.format_fields(connection: @name, transport: @transport_type,
                                                                              count: @tools_cache.size)}")
            @tools_cache
          end
        end

        def call_tool(name:, arguments: {}, context: {})
          connect unless connected?
          exchange_id = TracingContext.generate_exchange_id

          log.info("[mcp] client.tool_call.start #{Utils.format_fields(
            connection: @name, transport: @transport_type, tool_name: name,
            exchange_id: exchange_id, trace_id: context[:trace_id],
            arguments: Utils.summarize_params(arguments)
          )}")

          start_time = ::Process.clock_gettime(::Process::CLOCK_MONOTONIC)
          result = execute_tool_call(name: name, arguments: arguments, context: context)
          elapsed = ((::Process.clock_gettime(::Process::CLOCK_MONOTONIC) - start_time) * 1000).round(1)

          log.info("[mcp] client.tool_call.complete #{Utils.format_fields(
            connection: @name, transport: @transport_type, tool_name: name,
            exchange_id: exchange_id, duration_ms: elapsed,
            result: Utils.summarize_result(result)
          )}")

          emit_client_audit(tool_name: name, arguments: arguments, result: result,
                            context: context, exchange_id: exchange_id, duration_ms: elapsed)

          result
        rescue StandardError => e
          handle_exception(e, level: :warn, operation: 'legion.mcp.client.connection.call_tool')
          raise
        end

        private

        def connect_stdio
          command = @config[:command]
          raise ArgumentError, 'stdio transport requires a :command config key' unless command

          log.debug("[mcp][client] action=connect_stdio connection=#{@name}")
          parts = command.is_a?(Array) ? command : Shellwords.split(command)
          cmd = parts.shift
          @mcp_transport = ::MCP::Client::Stdio.new(command: cmd, args: parts)
          @mcp_client = ::MCP::Client.new(transport: @mcp_transport)
        end

        def connect_http
          url = @config[:url]
          raise ArgumentError, 'http transport requires a :url config key' unless url

          log.debug("[mcp][client] action=connect_http connection=#{@name} url=#{url}")
          @base_headers = (@config[:headers] || {}).dup
          @base_headers['Authorization'] ||= @config[:auth] if @config[:auth]

          @mcp_transport = ::MCP::Client::HTTP.new(url: url, headers: @base_headers)
          @mcp_client = ::MCP::Client.new(transport: @mcp_transport)
        end

        def inject_trace_headers(context)
          return unless http_transport? && traceable_context?(context)

          headers = build_trace_headers(context)
          @mcp_transport.instance_variable_set(:@headers, headers) if @mcp_transport.instance_variable_defined?(:@headers)
        end

        def http_transport?
          %i[http streamable_http].include?(@transport_type) &&
            @mcp_transport.respond_to?(:instance_variable_get)
        end

        def traceable_context?(context)
          context.is_a?(Hash) && !context.empty? &&
            (context[:trace_id] || context[:conversation_id])
        end

        def build_trace_headers(context)
          headers = @base_headers&.dup || {}
          headers['x-legion-trace-id'] = context[:trace_id] if context[:trace_id]
          headers['x-legion-conversation-id'] = context[:conversation_id] if context[:conversation_id]
          headers['traceparent'] = "00-#{context[:trace_id]}-#{SecureRandom.hex(8)}-01" if context[:trace_id]
          headers
        end

        # Verify the connection by requesting the tool list. This triggers
        # the MCP initialize handshake on stdio transports and confirms the
        # HTTP endpoint is reachable. The result seeds the tools cache.
        def verify_connection!
          log.debug("[mcp][client] action=verify_connection connection=#{@name}")
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

          log.debug("[mcp][client] action=fetch_tools connection=#{@name}")
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

        def execute_tool_call(name:, arguments:, context: {})
          connect unless connected?
          inject_trace_headers(context)

          log.debug("[mcp][client] action=execute_tool_call connection=#{@name} tool=#{name}")
          response = @mcp_client.call_tool(name: name, arguments: arguments)
          result = response.is_a?(Hash) ? response['result'] || response : response

          content = result.is_a?(Hash) ? result['content'] || result.fetch('content', []) : []
          is_error = result.is_a?(Hash) ? result.fetch('isError', false) : false

          { content: content, error: is_error }
        rescue ::MCP::Client::ServerError => e
          handle_exception(e, level: :warn, operation: 'legion.mcp.client.connection.execute_tool_call')
          { content: [{ type: 'text', text: e.message }], error: true }
        rescue ::MCP::Client::RequestHandlerError => e
          raise ConnectionError, "Tool call failed on #{@name}: #{e.message}"
        end

        def emit_client_audit(event)
          return unless defined?(Legion::MCP::Audit)

          context = event[:context] || {}
          result = event[:result]
          status = result.is_a?(Hash) && result[:error] ? :error : :success

          Legion::MCP::Audit.emit_client_call(
            conversation_id: context[:conversation_id],
            request_id:      context[:request_id],
            exchange_id:     event[:exchange_id],
            tool_name:       event[:tool_name],
            server:          @name,
            transport:       @transport_type,
            arguments:       event[:arguments],
            result:          Utils.summarize_result(result),
            status:          status,
            duration_ms:     event[:duration_ms],
            trace_id:        context[:trace_id],
            timestamp:       Time.now.utc.iso8601
          )
        rescue StandardError => e
          handle_exception(e, level: :warn, handled: true, operation: 'mcp.client.emit_audit')
        end
      end

      class ConnectionError < StandardError; end
    end
  end
end
