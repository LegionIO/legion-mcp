# frozen_string_literal: true

require_relative 'observer'
require_relative 'usage_filter'
require_relative 'tools/run_task'
require_relative 'tools/describe_runner'
require_relative 'tools/list_tasks'
require_relative 'tools/get_task'
require_relative 'tools/delete_task'
require_relative 'tools/get_task_logs'
require_relative 'tools/list_chains'
require_relative 'tools/create_chain'
require_relative 'tools/update_chain'
require_relative 'tools/delete_chain'
require_relative 'tools/list_relationships'
require_relative 'tools/create_relationship'
require_relative 'tools/update_relationship'
require_relative 'tools/delete_relationship'
require_relative 'tools/list_extensions'
require_relative 'tools/get_extension'
require_relative 'tools/enable_extension'
require_relative 'tools/disable_extension'
require_relative 'tools/list_schedules'
require_relative 'tools/create_schedule'
require_relative 'tools/update_schedule'
require_relative 'tools/delete_schedule'
require_relative 'tools/get_status'
require_relative 'tools/get_config'
require_relative 'tools/list_workers'
require_relative 'tools/show_worker'
require_relative 'tools/worker_lifecycle'
require_relative 'tools/worker_costs'
require_relative 'tools/team_summary'
require_relative 'tools/routing_stats'
require_relative 'tools/rbac_check'
require_relative 'tools/rbac_assignments'
require_relative 'tools/rbac_grants'
require_relative 'tools/prompt_list'
require_relative 'tools/prompt_show'
require_relative 'tools/prompt_run'
require_relative 'tools/dataset_list'
require_relative 'tools/dataset_show'
require_relative 'tools/experiment_results'
require_relative 'tools/eval_list'
require_relative 'tools/eval_run'
require_relative 'tools/eval_results'
require_relative 'context_compiler'
require_relative 'embedding_index'
require_relative 'cold_start'
require_relative 'gap_detector'
require_relative 'function_discovery'
require_relative 'self_generate'
require_relative 'tools/do_action'
require_relative 'tools/plan_action'
require_relative 'tools/discover_tools'
require_relative 'tools/ask_peer'
require_relative 'tools/list_peers'
require_relative 'tools/notify_peer'
require_relative 'tools/broadcast_peers'
require_relative 'tools/mesh_status'
require_relative 'tools/mind_growth_status'
require_relative 'tools/mind_growth_propose'
require_relative 'tools/mind_growth_approve'
require_relative 'tools/mind_growth_build_queue'
require_relative 'tools/mind_growth_cognitive_profile'
require_relative 'tools/mind_growth_health'
require_relative 'tools/query_knowledge'
require_relative 'tools/knowledge_health'
require_relative 'tools/knowledge_context'
require_relative 'tools/absorb'
require_relative 'deferred_registry'
require_relative 'catalog_bridge'
require_relative 'resources/runner_catalog'
require_relative 'resources/extension_info'

module Legion
  module MCP
    module Server
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
        Tools::Absorb
      ].freeze

      @tool_registry = Concurrent::Array.new(STATIC_TOOLS)
      @tool_registry_lock = Mutex.new

      class << self
        include CatalogBridge

        attr_reader :tool_registry

        def register_tool(tool_class)
          @tool_registry_lock.synchronize do
            return if tool_registry.any? { |tc| tc.tool_name == tool_class.tool_name }

            tool_registry << tool_class
            reset_caches!
          end
        end

        def unregister_tool(tool_name)
          @tool_registry_lock.synchronize do
            tool_registry.reject! { |tc| tc.tool_name == tool_name }
            reset_caches!
          end
        end

        def reset_caches!
          ContextCompiler.reset! if defined?(ContextCompiler)
          EmbeddingIndex.reset! if defined?(EmbeddingIndex) && EmbeddingIndex.respond_to?(:reset!)
        end

        def build(identity: nil)
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

          # Hydrate pattern store from L2 persistence (SQLite) on boot
          PatternStore.hydrate_from_l2 if defined?(PatternStore)

          # Cold-start: load community patterns if store is still empty after hydration
          ColdStart.load_community_patterns if defined?(ColdStart)

          # Discover and register runner functions before building the embedding index
          # so all tools are present when embeddings are populated
          FunctionDiscovery.discover_and_register if defined?(Legion::Extensions)

          # Populate embedding index for semantic tool matching (lazy — no-op if LLM unavailable)
          populate_embedding_index

          Resources::RunnerCatalog.register(server)
          Resources::ExtensionInfo.register_read_handler(server)

          register_catalog_listener
          hydrate_override_confidence

          server
        end

        def populate_embedding_index(embedder: EmbeddingIndex.default_embedder)
          return unless embedder

          tool_data = ContextCompiler.tool_index.values
          EmbeddingIndex.build_from_tool_data(tool_data, embedder: embedder)
        end

        def wire_observer(data)
          return unless data[:method] == 'tools/call' && data[:tool_name]

          duration_ms = (data[:duration].to_f * 1000).to_i
          params_keys = data[:tool_arguments].respond_to?(:keys) ? data[:tool_arguments].keys : []
          success     = data[:error].nil?

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

          Observer.record_intent_with_result(
            intent:    data[:tool_arguments][:intent],
            tool_name: data[:tool_name],
            success:   success
          )
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

        private

        def install_deferred_tools_list_handler(server)
          handlers = server.instance_variable_get(:@handlers)
          return unless handlers

          handlers[::MCP::Methods::TOOLS_LIST] = lambda { |_request|
            DeferredRegistry.build_tools_list(build_filtered_tool_list)
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
