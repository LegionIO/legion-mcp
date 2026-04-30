# frozen_string_literal: true

require_relative 'observer'
require_relative 'logging_support'
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
    module Server
      # MCP-specific tools not owned by any extension.
      # All extension-owned tools are discovered via Legion::Tools::Registry.
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
        attr_reader :tool_registry, :current_identity

        def rebuild_tool_registry
          @tool_registry_lock.synchronize do
            @tool_registry = Concurrent::Array.new(MCP_SPECIFIC_TOOLS)
            load_extension_tools
            DeferredRegistry.reset_cache! if defined?(DeferredRegistry) && DeferredRegistry.respond_to?(:reset_cache!)
            reset_caches!
          end
        end

        def register_tool(tool_class)
          @tool_registry_lock.synchronize do
            return if tool_registry.any? { |tc| tc.tool_name == tool_class.tool_name }

            tool_registry << tool_class
            reset_caches!
            LoggingSupport.info(
              'server.tool.registered',
              tool_name:     tool_class.tool_name,
              registry_size: tool_registry.size
            )
          end
        end

        def unregister_tool(tool_name)
          @tool_registry_lock.synchronize do
            tool_registry.reject! { |tc| tc.tool_name == tool_name }
            reset_caches!
            LoggingSupport.info(
              'server.tool.unregistered',
              tool_name:     tool_name,
              registry_size: tool_registry.size
            )
          end
        end

        def reset_caches!
          ContextCompiler.reset! if defined?(ContextCompiler)
          EmbeddingIndex.reset! if defined?(EmbeddingIndex) && EmbeddingIndex.respond_to?(:reset!)
        end

        def build(identity: nil) # rubocop:disable Metrics/MethodLength
          run_function_discovery
          rebuild_tool_registry
          @current_identity = identity

          LoggingSupport.info(
            'server.build.start',
            identity:      LoggingSupport.summarize_identity(identity),
            registry_size: tool_registry.size,
            governance:    ToolGovernance.governance_enabled?
          )
          tools = ToolGovernance.filter_tools(tool_registry.dup, identity)

          server = ::MCP::Server.new(
            name:               'legion',
            version:            defined?(Legion::VERSION) ? Legion::VERSION : Legion::MCP::VERSION,
            instructions:       instructions,
            tools:              tools,
            resources:          Resources::ExtensionInfo.static_resources,
            resource_templates: Resources::ExtensionInfo.resource_templates
          )

          if defined?(Observer)
            ::MCP.configure do |c|
              c.instrumentation_callback = ->(idata) { Server.wire_observer(idata) }
            end
          end

          install_deferred_tools_list_handler(server)

          PatternStore.hydrate_from_l2 if defined?(PatternStore)
          ColdStart.load_community_patterns if defined?(ColdStart)
          populate_embedding_index

          Resources::RunnerCatalog.register(server)
          Resources::ExtensionInfo.register_read_handler(server)

          hydrate_override_confidence

          LoggingSupport.info(
            'server.build.complete',
            identity:       LoggingSupport.summarize_identity(identity),
            tool_count:     tools.size,
            registry_size:  tool_registry.size,
            resource_count: server.resources.size
          )
          server
        end

        def populate_embedding_index(embedder: EmbeddingIndex.default_embedder)
          return unless embedder

          tool_data = ContextCompiler.tool_index.values
          EmbeddingIndex.build_from_tool_data(tool_data, embedder: embedder)
          LoggingSupport.info(
            'server.embedding_index.populated',
            tool_count: tool_data.size
          )
        end

        def wire_observer(data)
          return unless data[:method] == 'tools/call' && data[:tool_name]

          duration_ms = (data[:duration].to_f * 1000).to_i
          params_keys = data[:tool_arguments].respond_to?(:keys) ? data[:tool_arguments].keys : []
          success     = data[:error].nil?
          request_id  = LoggingSupport.request_id_from(data[:tool_arguments])

          LoggingSupport.info(
            'server.tool_call.complete',
            request_id:  request_id,
            tool_name:   data[:tool_name],
            success:     success,
            duration_ms: duration_ms,
            params_keys: params_keys,
            error:       data[:error]
          )

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
          ranked.filter_map do |name|
            governed.find do |tc|
              (tc.respond_to?(:tool_name) ? tc.tool_name : tc.name) == name
            end
          end
        end

        private

        def load_extension_tools
          if settings_extensions_available?
            load_tools_from_settings_extensions
          elsif defined?(Legion::Tools::Registry) && Legion::Tools::Registry.respond_to?(:all_tools)
            load_tools_from_legacy_registry
          end
        end

        def settings_extensions_available?
          defined?(Legion::Settings::Extensions) &&
            Legion::Settings::Extensions.respond_to?(:tools) &&
            Legion::Settings::Extensions.tools.any?
        end

        def load_tools_from_settings_extensions
          Legion::Settings::Extensions.tools.each do |tool_entry|
            sanitized_name = ToolAdapter.sanitize_tool_name(tool_entry[:name])
            next if @tool_registry.any? { |tc| tc.tool_name == sanitized_name }

            adapter = ToolAdapter.from_registry_entry(tool_entry)
            @tool_registry << adapter if adapter
          end
        end

        def load_tools_from_legacy_registry
          Legion::Tools::Registry.all_tools.each do |legion_tool_class|
            next if @tool_registry.any? { |tc| tc.tool_name == legion_tool_class.tool_name }

            adapted = ToolAdapter.from_legion_tool(legion_tool_class)
            @tool_registry << adapted
          end
        end

        def run_function_discovery
          FunctionDiscovery.reset_discovery!
          FunctionDiscovery.discover_and_register
        end

        def hydrate_override_confidence
          return unless defined?(Legion::LLM::OverrideConfidence)
          return unless Legion::LLM::OverrideConfidence.respond_to?(:hydrate_from_l2)

          Legion::LLM::OverrideConfidence.hydrate_from_l2
          Legion::LLM::OverrideConfidence.hydrate_from_apollo if Legion::LLM::OverrideConfidence.respond_to?(:hydrate_from_apollo)
        end

        def install_deferred_tools_list_handler(server)
          handlers = server.instance_variable_get(:@handlers)
          return unless handlers

          handlers[::MCP::Methods::TOOLS_LIST] = lambda { |_request|
            tool_list = DeferredRegistry.build_tools_list(build_filtered_tool_list)
            LoggingSupport.info(
              'server.tools.list',
              total:         tool_list.size,
              deferred_only: tool_list.count { |entry| !entry.key?(:inputSchema) && !entry.key?(:input_schema) }
            )
            tool_list
          }
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
