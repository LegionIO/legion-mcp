# frozen_string_literal: true

module Legion
  module MCP
    module DynamicInjector
      MAX_INJECTED = 10

      module_function

      def enabled?
        Legion::Settings.dig(:mcp, :dynamic_tools, :enabled) == true
      end

      def max_injected
        Legion::Settings.dig(:mcp, :dynamic_tools, :max_injected) || MAX_INJECTED
      end

      def context_tools(intent_string)
        return [] unless enabled?
        return [] if intent_string.nil? || intent_string.strip.empty?

        matches = ContextCompiler.match_tools(intent_string, limit: max_injected)
        return [] if matches.empty?

        always = DeferredRegistry.always_loaded_tools
        matches.filter_map do |match|
          next if always.include?(match[:name])
          next if match[:score] <= 0

          Server.tool_registry.find { |tc| tc.tool_name == match[:name] }
        end
      end

      def active_tool_set(intent_string)
        always = always_loaded_classes
        injected = context_tools(intent_string)
        (always + injected).uniq(&:tool_name)
      end

      def always_loaded_classes
        names = DeferredRegistry.always_loaded_tools
        Server.tool_registry.select { |tc| names.include?(tc.tool_name) }
      end

      def tools_changed?(previous_names, current_names)
        previous_names.sort != current_names.sort
      end

      def notify_if_changed(server, previous_names, current_names)
        return unless tools_changed?(previous_names, current_names)
        return unless server.respond_to?(:notify_tools_list_changed)

        server.notify_tools_list_changed
      rescue StandardError => e
        Legion::Logging.debug("DynamicInjector: notify failed: #{e.message}") if defined?(Legion::Logging)
      end

      def inject_for_context(server, intent_string, previous_names: [])
        return previous_names unless enabled?

        tools = active_tool_set(intent_string)
        current_names = tools.map(&:tool_name)

        notify_if_changed(server, previous_names, current_names)
        current_names
      end
    end
  end
end
