# frozen_string_literal: true

module Legion
  module MCP
    module DeferredRegistry
      extend Legion::Logging::Helper

      # Tools that are ALWAYS fully loaded (never deferred).
      # These are high-frequency entry points or meta-tools.
      ALWAYS_LOADED = %w[
        legion.do
        legion.tools
        legion.run_task
        legion.list_tasks
        legion.get_task
        legion.get_status
        legion.describe_runner
        legion.plan_action
        legion.query_knowledge
        legion.knowledge_context
        legion.knowledge_health
        legion.absorb
        legion.get_task_logs
      ].freeze

      module_function

      def reset_cache!
        @always_loaded_cache = nil
      end

      def enabled?
        setting = Legion::Settings.dig(:mcp, :deferred_loading, :enabled)
        setting.nil? || setting
      end

      def always_loaded_tools
        return @always_loaded_cache if @always_loaded_cache

        base = ALWAYS_LOADED.dup
        if Legion::Settings::Extensions.respond_to?(:filter_tools)
          always_entries = Legion::Settings::Extensions.filter_tools(deferred: false)
          base |= always_entries.map { |e| Legion::MCP::ToolAdapter.sanitize_tool_name(e[:name]) } if always_entries.is_a?(Array)
        end
        custom = Legion::Settings.dig(:mcp, :deferred_loading, :always_loaded)
        @always_loaded_cache = custom.is_a?(Array) ? (base | custom) : base
      end

      def deferred?(tool_class)
        return false unless enabled?

        name = tool_class.respond_to?(:tool_name) ? tool_class.tool_name : tool_class.name
        !always_loaded_tools.include?(name)
      end

      def deferred_entry(tool_class)
        { name: tool_class.tool_name, description: tool_class.description }
      end

      def full_entry(tool_class)
        tool_class.to_h
      end

      def build_tools_list(tool_classes)
        deferred_count = 0
        result = tool_classes.map do |tc|
          if deferred?(tc)
            deferred_count += 1
            deferred_entry(tc)
          else
            full_entry(tc)
          end
        end
        log.debug("[mcp][deferred] action=build_tools_list total=#{result.size} " \
                  "deferred=#{deferred_count} full=#{result.size - deferred_count}")
        result
      end

      def resolve_schemas(tool_names, tool_classes)
        log.debug("[mcp][deferred] action=resolve_schemas requested=#{tool_names.size}")
        result = tool_names.filter_map do |name|
          tc = tool_classes.find { |klass| klass.tool_name == name }
          next unless tc

          tc.to_h
        end
        log.debug("[mcp][deferred] action=resolve_schemas.complete resolved=#{result.size}")
        result
      end
    end
  end
end
