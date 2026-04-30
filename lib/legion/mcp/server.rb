# frozen_string_literal: true

require_relative 'observer'
require_relative 'tracing_context'
require_relative 'utils'
require_relative 'usage_filter'
require_relative 'tools_loader'
require_relative 'tool_adapter'
require_relative 'context_compiler'
require_relative 'embedding_index'
require_relative 'cold_start'
require_relative 'gap_detector'
require_relative 'function_discovery'
require_relative 'self_generate'
require_relative 'structural_index'
require_relative 'state_tracker'
require_relative 'tool_quality'
require_relative 'deferred_registry'
require_relative 'catalog_dispatcher'
require_relative 'dynamic_injector'
require_relative 'resources/runner_catalog'
require_relative 'resources/extension_info'

module Legion
  module MCP
    module Server # rubocop:disable Metrics/ModuleLength
      extend Legion::Logging::Helper

      # MCP-specific tools not owned by any extension.
      # All extension-owned tools are discovered via Legion::Settings::Extensions.
      MCP_SPECIFIC_TOOLS = [
        Tools::PlanAction,
        Tools::DiscoverTools,
        Tools::StructuralIndexTool,
        Tools::ToolAudit,
        Tools::StateDiff,
        Tools::SearchSessions,
        Tools::SkillList,
        Tools::SkillDescribe,
        Tools::SkillInvoke,
        Tools::SkillCancel
      ].freeze

      @tool_registry = Concurrent::Array.new(MCP_SPECIFIC_TOOLS)
      @tool_registry_lock = Mutex.new

      class << self # rubocop:disable Metrics/ClassLength
        attr_reader :tool_registry, :current_identity, :conversation_id, :trace_id

        def rebuild_tool_registry
          log.debug("[mcp][server] action=rebuild_tool_registry mcp_specific=#{MCP_SPECIFIC_TOOLS.size}")
          @tool_registry_lock.synchronize do
            @tool_registry = Concurrent::Array.new(MCP_SPECIFIC_TOOLS)
            load_extension_tools
            DeferredRegistry.reset_cache! if defined?(DeferredRegistry) && DeferredRegistry.respond_to?(:reset_cache!)
            reset_caches!
          end
          log.debug("[mcp][server] action=rebuild_tool_registry.complete registry_size=#{tool_registry.size}")
        end

        def register_tool(tool_class)
          @tool_registry_lock.synchronize do
            return if tool_registry.any? { |tc| tc.tool_name == tool_class.tool_name }

            tool_registry << tool_class
            reset_caches!
            mcp_log :info, 'server.tool.registered',
                    tool_name: tool_class.tool_name, registry_size: tool_registry.size
          end
        end

        def unregister_tool(tool_name)
          @tool_registry_lock.synchronize do
            tool_registry.reject! { |tc| tc.tool_name == tool_name }
            reset_caches!
            mcp_log :info, 'server.tool.unregistered',
                    tool_name: tool_name, registry_size: tool_registry.size
          end
        end

        def reset_caches!
          ContextCompiler.reset! if defined?(ContextCompiler)
          EmbeddingIndex.reset! if defined?(EmbeddingIndex) && EmbeddingIndex.respond_to?(:reset!)
        end

        def build(identity: nil)
          prepare_build(identity)
          tools = ToolGovernance.filter_tools(tool_registry.dup, identity)

          server = ::MCP::Server.new(
            name:               'legion',
            version:            defined?(Legion::VERSION) ? Legion::VERSION : Legion::MCP::VERSION,
            instructions:       instructions,
            tools:              tools,
            resources:          Resources::ExtensionInfo.static_resources,
            resource_templates: Resources::ExtensionInfo.resource_templates
          )

          configure_server(server)

          mcp_log :info, 'server.build.complete',
                  identity: Utils.summarize_identity(identity),
                  tool_count: tools.size, registry_size: tool_registry.size,
                  resource_count: server.resources.size
          server
        end

        def populate_embedding_index(embedder: EmbeddingIndex.default_embedder)
          return unless embedder

          tool_data = ContextCompiler.tool_index.values
          EmbeddingIndex.build_from_tool_data(tool_data, embedder: embedder)
          mcp_log :info, 'server.embedding_index.populated', tool_count: tool_data.size
        end

        def wire_observer(data)
          return unless data[:method] == 'tools/call' && data[:tool_name]

          duration_ms = (data[:duration].to_f * 1000).to_i
          params_keys = data[:tool_arguments].respond_to?(:keys) ? data[:tool_arguments].keys : []
          success     = data[:error].nil?
          request_id  = Utils.request_id_from(data[:tool_arguments])

          mcp_log :info, 'server.tool_call.complete',
                  request_id: request_id, tool_name: data[:tool_name],
                  success: success, duration_ms: duration_ms,
                  params_keys: params_keys, error: data[:error]

          Observer.record(
            tool_name:   data[:tool_name],
            duration_ms: duration_ms,
            success:     success,
            params_keys: params_keys,
            error:       data[:error]
          )

          # Pattern promotion for legion.do is handled inside DoAction itself
          # (which knows the actual resolved tool name). For other tools called
          # directly, we record the intent+result here if an intent is present.
          return if data[:tool_name] == 'legion.do'
          return unless data[:tool_arguments]&.dig(:intent)

          observer_args = {
            intent:    data[:tool_arguments][:intent],
            tool_name: data[:tool_name],
            success:   success
          }
          observer_args[:request_id] = request_id if request_id

          Observer.record_intent_with_result(**observer_args)
        end

        def build_filtered_tool_list(keywords: [])
          governed = ToolGovernance.filter_tools(tool_registry, @current_identity)
          tool_names = governed.map { |tc| tc.respond_to?(:tool_name) ? tc.tool_name : tc.name }
          ranked     = UsageFilter.ranked_tools(tool_names, keywords: keywords)
          result = ranked.filter_map do |name|
            governed.find do |tc|
              (tc.respond_to?(:tool_name) ? tc.tool_name : tc.name) == name
            end
          end
          log.debug("[mcp][server] action=build_filtered_tool_list tools_before=#{tool_registry.size} " \
                    "governed=#{governed.size} tools_after=#{result.size} " \
                    "identity=#{Utils.summarize_identity(@current_identity)} keywords=#{keywords.size}")
          result
        end

        private

        def prepare_build(identity)
          run_function_discovery
          rebuild_tool_registry
          @current_identity = identity
          @conversation_id = TracingContext.generate_conversation_id
          @trace_id = TracingContext.generate_trace_id

          mcp_log :info, 'server.build.start',
                  identity:        Utils.summarize_identity(identity),
                  registry_size:   tool_registry.size,
                  governance:      ToolGovernance.governance_enabled?,
                  conversation_id: @conversation_id
        end

        def configure_server(server)
          if defined?(Observer)
            ::MCP.configure do |c|
              c.instrumentation_callback = ->(idata) { Server.wire_observer(idata) }
            end
          end

          install_deferred_tools_list_handler(server)
          install_tracing_tool_call_handler(server)
          register_mcp_tools_in_settings_extensions

          PatternStore.hydrate_from_l2 if defined?(PatternStore)
          ColdStart.load_community_patterns if defined?(ColdStart)
          populate_embedding_index

          Resources::RunnerCatalog.register(server)
          Resources::ExtensionInfo.register_read_handler(server)

          hydrate_override_confidence
        end

        def mcp_log(level, event, **fields)
          log.public_send(level, "[mcp] #{event} #{Utils.format_fields(fields)}")
        end

        def load_extension_tools
          available = settings_extensions_available?
          log.debug("[mcp][server] action=load_extension_tools settings_extensions_available=#{available}")
          load_tools_from_settings_extensions if available
        end

        def register_mcp_tools_in_settings_extensions
          return unless defined?(Legion::Settings::Extensions) && Legion::Settings::Extensions.respond_to?(:register_tool)

          log.debug("[mcp][server] action=register_mcp_tools_in_settings_extensions count=#{MCP_SPECIFIC_TOOLS.size}")
          MCP_SPECIFIC_TOOLS.each do |tool_class|
            Legion::Settings::Extensions.register_tool(tool_class.tool_name, {
                                                         description:   tool_class.description,
                                                         input_schema:  tool_class.input_schema,
                                                         tool_class:    tool_class,
                                                         dispatch_type: :class_call,
                                                         extension:     'legion-mcp',
                                                         source:        :mcp_builtin,
                                                         mcp_tier:      tool_class.respond_to?(:mcp_tier) ? tool_class.mcp_tier : nil
                                                       })
          end
        end

        def settings_extensions_available?
          defined?(Legion::Settings::Extensions) &&
            Legion::Settings::Extensions.respond_to?(:tools) &&
            Legion::Settings::Extensions.tools.any?
        end

        def load_tools_from_settings_extensions
          entries = Legion::Settings::Extensions.tools
          log.debug("[mcp][server] action=load_tools_from_settings_extensions entries=#{entries.size}")
          loaded = 0
          entries.each do |tool_entry|
            sanitized_name = ToolAdapter.sanitize_tool_name(tool_entry[:name])
            next if @tool_registry.any? { |tc| tc.tool_name == sanitized_name }

            adapter = ToolAdapter.from_registry_entry(tool_entry)
            if adapter
              @tool_registry << adapter
              loaded += 1
            end
          end
          log.debug("[mcp][server] action=load_tools_from_settings_extensions.complete loaded=#{loaded}")
        end

        def run_function_discovery
          log.debug('[mcp][server] action=run_function_discovery')
          FunctionDiscovery.reset_discovery!
          FunctionDiscovery.discover_and_register
        end

        def hydrate_override_confidence
          return unless defined?(Legion::LLM::OverrideConfidence)
          return unless Legion::LLM::OverrideConfidence.respond_to?(:hydrate_from_l2)

          log.debug('[mcp][server] action=hydrate_override_confidence')
          Legion::LLM::OverrideConfidence.hydrate_from_l2
          Legion::LLM::OverrideConfidence.hydrate_from_apollo if Legion::LLM::OverrideConfidence.respond_to?(:hydrate_from_apollo)
        end

        def install_deferred_tools_list_handler(server)
          handlers = server.instance_variable_get(:@handlers)
          return unless handlers

          handlers[::MCP::Methods::TOOLS_LIST] = lambda { |_request|
            tool_list = DeferredRegistry.build_tools_list(build_filtered_tool_list)
            deferred = tool_list.count { |e| !e.key?(:inputSchema) && !e.key?(:input_schema) }
            mcp_log :info, 'server.tools.list', total: tool_list.size, deferred_only: deferred
            tool_list
          }
        end

        def install_tracing_tool_call_handler(server)
          tracing_mod = build_tracing_module
          server.singleton_class.prepend(tracing_mod)
        end

        def build_tracing_module
          server_mod = self
          Module.new do
            define_method(:call_tool) do |request, session: nil, related_request_id: nil|
              request_id   = TracingContext.generate_request_id(request&.dig(:_meta, :progressToken))
              exchange_id  = TracingContext.generate_exchange_id
              tool_call_id = TracingContext.generate_tool_call_id

              TracingContext.set(
                conversation_id: server_mod.conversation_id,
                request_id:      request_id,
                exchange_id:     exchange_id,
                tool_call_id:    tool_call_id,
                trace_id:        server_mod.trace_id
              )

              start_time = ::Process.clock_gettime(::Process::CLOCK_MONOTONIC)
              result = super(request, session: session, related_request_id: related_request_id)
              elapsed = ((::Process.clock_gettime(::Process::CLOCK_MONOTONIC) - start_time) * 1000).round(1)

              server_mod.send(:emit_server_audit,
                              params: request, result: result, request_id: request_id,
                              exchange_id: exchange_id, tool_call_id: tool_call_id, duration_ms: elapsed)

              result
            ensure
              TracingContext.clear
            end
          end
        end

        def emit_server_audit(params:, result:, request_id:, exchange_id:, tool_call_id:, duration_ms:) # rubocop:disable Metrics/ParameterLists
          return unless defined?(Legion::MCP::Audit)

          tool_name = params&.dig(:name)
          status = result.is_a?(Hash) && result[:isError] ? :error : :success

          Legion::MCP::Audit.emit_tool_call(
            conversation_id: @conversation_id,
            request_id:      request_id,
            exchange_id:     exchange_id,
            tool_call_id:    tool_call_id,
            tool_name:       tool_name,
            arguments:       Utils.summarize_params(params&.dig(:arguments)),
            result:          Utils.summarize_result(result),
            status:          status,
            duration_ms:     duration_ms,
            caller:          @current_identity,
            source:          { type: :mcp_server },
            trace_id:        @trace_id,
            timestamp:       Time.now.utc.iso8601
          )
        rescue StandardError => e
          handle_exception(e, level: :warn, handled: true, operation: 'mcp.server.emit_audit')
        end

        def instructions
          <<~TEXT
            Legion is an async job engine. You can run tasks, create chains and relationships between services, manage extensions, and query system status.

            Use `legion.run_task` with dot notation (e.g., "http.request.get") for quick task execution.
            Use `legion.describe_runner` to discover available functions on a runner.
            CRUD tools follow the pattern: legion.list_*, legion.create_*, legion.get_*, legion.update_*, legion.delete_*.
          TEXT
        end
      end
    end
  end
end
