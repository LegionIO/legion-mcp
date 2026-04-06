# frozen_string_literal: true

require_relative 'observer'
require_relative 'logging_support'
require_relative 'usage_filter'
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
require_relative 'catalog_bridge'
require_relative 'resources/runner_catalog'
require_relative 'resources/extension_info'

module Legion
  module MCP
    module Server # rubocop:disable Metrics/ModuleLength
      MCP_SPECIFIC_TOOLS = [
        Tools::PlanAction,
        Tools::DiscoverTools,
        Tools::StateDiff,
        Tools::StructuralIndexTool,
        Tools::ToolAudit,
        Tools::SearchSessions
      ].freeze

      # All built-in tool classes loaded via tools_loader.rb
      STATIC_TOOLS = [
        Tools::RunTask,
        Tools::DescribeRunner,
        Tools::ListTasks,
        Tools::GetTask,
        Tools::DeleteTask,
        Tools::GetTaskLogs,
        Tools::ListChains,
        Tools::CreateChain,
        Tools::UpdateChain,
        Tools::DeleteChain,
        Tools::ListRelationships,
        Tools::CreateRelationship,
        Tools::UpdateRelationship,
        Tools::DeleteRelationship,
        Tools::ListExtensions,
        Tools::GetExtension,
        Tools::EnableExtension,
        Tools::DisableExtension,
        Tools::ListSchedules,
        Tools::CreateSchedule,
        Tools::UpdateSchedule,
        Tools::DeleteSchedule,
        Tools::GetStatus,
        Tools::GetConfig,
        Tools::ListWorkers,
        Tools::ShowWorker,
        Tools::WorkerLifecycle,
        Tools::WorkerCosts,
        Tools::TeamSummary,
        Tools::RoutingStats,
        Tools::RbacCheck,
        Tools::RbacAssignments,
        Tools::RbacGrants,
        Tools::PromptList,
        Tools::PromptShow,
        Tools::PromptRun,
        Tools::DatasetList,
        Tools::DatasetShow,
        Tools::ExperimentResults,
        Tools::EvalList,
        Tools::EvalRun,
        Tools::EvalResults,
        Tools::DoAction,
        Tools::PlanAction,
        Tools::DiscoverTools,
        Tools::AskPeer,
        Tools::ListPeers,
        Tools::NotifyPeer,
        Tools::BroadcastPeers,
        Tools::MeshStatus,
        Tools::MindGrowthStatus,
        Tools::MindGrowthPropose,
        Tools::MindGrowthApprove,
        Tools::MindGrowthBuildQueue,
        Tools::MindGrowthCognitiveProfile,
        Tools::MindGrowthHealth,
        Tools::QueryKnowledge,
        Tools::KnowledgeHealth,
        Tools::KnowledgeContext,
        Tools::Absorb,
        Tools::StructuralIndexTool,
        Tools::ToolAudit,
        Tools::StateDiff,
        Tools::SearchSessions
      ].freeze

      @tool_registry = Concurrent::Array.new(STATIC_TOOLS)
      @tool_registry_lock = Mutex.new

      class << self # rubocop:disable Metrics/ClassLength
        attr_reader :tool_registry

        def rebuild_tool_registry
          @tool_registry_lock.synchronize do
            @tool_registry = Concurrent::Array.new(STATIC_TOOLS)

            if defined?(Legion::Tools::Registry) && Legion::Tools::Registry.respond_to?(:all_tools)
              Legion::Tools::Registry.all_tools.each do |legion_tool_class|
                next if @tool_registry.any? { |tc| tc.tool_name == legion_tool_class.tool_name }

                adapted = ToolAdapter.from_legion_tool(legion_tool_class)
                @tool_registry << adapted
              end
            end

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
          rebuild_tool_registry
          register_catalog_listener

          LoggingSupport.info(
            'server.build.start',
            identity:      LoggingSupport.summarize_identity(identity),
            registry_size: tool_registry.size,
            governance:    ToolGovernance.governance_enabled?
          )
          tools = if ToolGovernance.governance_enabled?
                    ToolGovernance.filter_tools(tool_registry, identity)
                  else
                    tool_registry
                  end

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
          run_function_discovery
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
          tool_names = tool_registry.map { |tc| tc.respond_to?(:tool_name) ? tc.tool_name : tc.name }
          ranked     = UsageFilter.ranked_tools(tool_names, keywords: keywords)
          ranked.filter_map do |name|
            tool_registry.find do |tc|
              (tc.respond_to?(:tool_name) ? tc.tool_name : tc.name) == name
            end
          end
        end

        def dynamic_tool_list
          static = tool_registry.map do |klass|
            { name: klass.tool_name, description: klass.description,
              input_schema: klass.input_schema, source: :builtin, klass: klass }
          end

          dynamic = if defined?(Legion::Extensions::Catalog::Registry)
                      Legion::Extensions::Catalog::Registry.for_mcp.map(&:to_mcp_tool)
                    else
                      []
                    end

          static + dynamic
        end

        def dispatch_catalog_tool(tool_name, arguments)
          return nil unless defined?(Legion::Extensions::Catalog::Registry)

          cap = Legion::Extensions::Catalog::Registry.find_by_mcp_name(tool_name)
          return nil unless cap

          segments = cap.extension.delete_prefix('lex-').split('-')
          runner_path = (%w[Legion Extensions] + segments.map(&:capitalize) + ['Runners', cap.runner]).join('::')
          runner = Kernel.const_get(runner_path)
          fn = cap.function.to_sym
          result = runner.send(fn, **(arguments || {}).transform_keys(&:to_sym))
          { status: :success, result: result, source: :catalog }
        rescue NameError => e
          handle_exception(e, level: :warn, operation: 'legion.mcp.server.dispatch_catalog_tool')
          nil
        rescue StandardError => e
          handle_exception(e, level: :error, operation: 'legion.mcp.server.dispatch_catalog_tool')
          { status: :error, error: e.message, source: :catalog }
        end

        def register_catalog_listener
          return unless defined?(Legion::Extensions::Catalog::Registry)
          return unless Legion::Extensions::Catalog::Registry.respond_to?(:on_change)

          Legion::Extensions::Catalog::Registry.on_change { Legion::MCP.reset! }
        end

        private

        def run_function_discovery
          return unless defined?(Legion::Extensions)

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
