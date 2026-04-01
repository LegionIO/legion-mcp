# frozen_string_literal: true

module Legion
  module MCP
    module DeferredRegistry
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

      def enabled?
        setting = Legion::Settings.dig(:mcp, :deferred_loading, :enabled)
        setting.nil? || setting
      end

      def always_loaded_tools
        custom = Legion::Settings.dig(:mcp, :deferred_loading, :always_loaded)
        custom.is_a?(Array) ? (ALWAYS_LOADED | custom) : ALWAYS_LOADED
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
        tool_classes.map do |tc|
          if deferred?(tc)
            deferred_entry(tc)
          else
            full_entry(tc)
          end
        end
      end

      def resolve_schemas(tool_names, tool_classes)
        tool_names.filter_map do |name|
          tc = tool_classes.find { |klass| klass.tool_name == name }
          next unless tc

          tc.to_h
        end
      end
    end
  end
end
