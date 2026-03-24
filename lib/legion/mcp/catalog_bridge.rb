# frozen_string_literal: true

module Legion
  module MCP
    module CatalogBridge
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
        Legion::Logging.warn("Catalog dispatch failed: #{e.message}") if defined?(Legion::Logging)
        nil
      rescue StandardError => e
        { status: :error, error: e.message, source: :catalog }
      end

      def dynamic_tool_list
        static = Server::TOOL_CLASSES.map do |klass|
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
