# frozen_string_literal: true

module Legion
  module MCP
    module CatalogDispatcher
      module_function

      def dispatch(runner_class:, function:, params:, source: :mcp)
        return nil unless defined?(Legion::Ingress)

        Legion::Ingress.run(
          payload:       params,
          runner_class:  runner_class,
          function:      function.to_sym,
          source:        source,
          check_subtask: true,
          generate_task: true
        )
      end

      def build_tool_class(entry)
        runner_class_str = entry[:runner_class]
        function_name    = entry[:function]
        tool_name_val    = entry[:tool_name]
        desc             = entry[:description]
        schema           = entry[:input_schema] || { properties: {} }
        category         = entry[:category]
        tier             = entry[:tier]

        klass = Class.new(::MCP::Tool) do
          tool_name tool_name_val
          description desc
          input_schema(schema)
          define_singleton_method(:mcp_category) { category }
          define_singleton_method(:mcp_tier)     { tier }
          define_singleton_method(:catalog_entry) { true }
        end

        wire_dispatch(klass, runner_class_str, function_name)
        klass
      end

      def wire_dispatch(klass, runner_class_str, function_name)
        klass.define_singleton_method(:call) do |**params|
          result = CatalogDispatcher.dispatch(
            runner_class: runner_class_str,
            function:     function_name,
            params:       params
          )

          if result.nil?
            text = Legion::JSON.dump({ error: 'Ingress not available' })
            ::MCP::Tool::Response.new([{ type: 'text', text: text }], error: true)
          else
            text = defined?(Legion::JSON) ? Legion::JSON.dump(result) : result.to_s
            ::MCP::Tool::Response.new([{ type: 'text', text: text }])
          end
        rescue StandardError => e
          Legion::Logging.warn("CatalogDispatcher: #{function_name} failed: #{e.message}") if defined?(Legion::Logging)
          text = Legion::JSON.dump({ error: e.message })
          ::MCP::Tool::Response.new([{ type: 'text', text: text }], error: true)
        end
      end

      def generate_tools_from_catalog
        return [] unless defined?(Legion::Extensions::Catalog::Registry)
        return [] unless Legion::Extensions::Catalog::Registry.respond_to?(:for_mcp)

        Legion::Extensions::Catalog::Registry.for_mcp.filter_map do |cap|
          build_tool_class(
            runner_class: resolve_runner_class(cap),
            function:     cap.function,
            tool_name:    cap.respond_to?(:mcp_name) ? cap.mcp_name : "legion.catalog.#{cap.function}",
            description:  cap.respond_to?(:description) ? cap.description : "Auto-generated: #{cap.function}",
            input_schema: cap.respond_to?(:input_schema) ? cap.input_schema : { properties: {} },
            category:     cap.respond_to?(:category) ? cap.category : nil,
            tier:         cap.respond_to?(:tier) ? cap.tier : nil
          )
        rescue StandardError => e
          Legion::Logging.debug("CatalogDispatcher: skipping #{cap}: #{e.message}") if defined?(Legion::Logging)
          nil
        end
      end

      def resolve_runner_class(cap)
        segments = cap.extension.delete_prefix('lex-').split('-')
        (%w[Legion Extensions] + segments.map(&:capitalize) + ['Runners', cap.runner]).join('::')
      end
    end
  end
end
