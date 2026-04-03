# frozen_string_literal: true

module Legion
  module MCP
    module CatalogBridge
      include Legion::Logging::Helper

      def hydrate_override_confidence
        return unless defined?(Legion::LLM::OverrideConfidence)
        return unless Legion::LLM::OverrideConfidence.respond_to?(:hydrate_from_l2)

        Legion::LLM::OverrideConfidence.hydrate_from_l2
        Legion::LLM::OverrideConfidence.hydrate_from_apollo if Legion::LLM::OverrideConfidence.respond_to?(:hydrate_from_apollo)
      end

      def register_catalog_listener
        return unless defined?(Legion::Extensions::Catalog::Registry)
        return unless Legion::Extensions::Catalog::Registry.respond_to?(:on_change)

        Legion::Extensions::Catalog::Registry.on_change { Legion::MCP.reset! }
      end

      def dispatch_catalog_tool(tool_name, arguments)
        log.info('Starting legion.mcp.catalog_bridge.dispatch_catalog_tool')
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
        handle_exception(e, level: :warn, operation: 'legion.mcp.catalog_bridge.dispatch_catalog_tool')
        log.warn("Catalog dispatch failed: #{e.message}")
        nil
      rescue StandardError => e
        handle_exception(e, level: :error, operation: 'legion.mcp.catalog_bridge.dispatch_catalog_tool')
        { status: :error, error: e.message, source: :catalog }
      end

      def register_catalog_tools
        log.info('Starting legion.mcp.catalog_bridge.register_catalog_tools')
        CatalogDispatcher.generate_tools_from_catalog.each { |tc| Server.register_tool(tc) }
      end

      def dynamic_tool_list
        static = Server.tool_registry.map do |klass|
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
    end
  end
end
