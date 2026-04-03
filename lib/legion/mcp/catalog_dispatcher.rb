# frozen_string_literal: true

require_relative 'logging_support'

module Legion
  module MCP
    module CatalogDispatcher
      extend Legion::Logging::Helper

      module_function

      def dispatch(runner_class:, function:, params:, source: :mcp) # rubocop:disable Metrics/MethodLength
        LoggingSupport.info(
          'catalog.dispatch.start',
          runner_class: runner_class,
          function:     function,
          source:       source,
          params:       LoggingSupport.summarize_params(params)
        )
        unless defined?(Legion::Ingress)
          LoggingSupport.warn(
            'catalog.dispatch.skipped',
            runner_class: runner_class,
            function:     function,
            reason:       'ingress unavailable'
          )
          return nil
        end

        result = Legion::Ingress.run(
          payload:       params,
          runner_class:  runner_class,
          function:      function.to_sym,
          source:        source,
          check_subtask: true,
          generate_task: true
        )
        LoggingSupport.info(
          'catalog.dispatch.complete',
          runner_class: runner_class,
          function:     function,
          source:       source,
          result:       LoggingSupport.summarize_result(result)
        )
        result
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
        klass.extend(Legion::Logging::Helper)

        wire_dispatch(klass, runner_class_str, function_name, tool_name_val)
        klass
      end

      def wire_dispatch(klass, runner_class_str, function_name, tool_name_val) # rubocop:disable Metrics/MethodLength
        klass.define_singleton_method(:call) do |**params| # rubocop:disable Metrics/BlockLength
          LoggingSupport.info(
            'catalog.tool_call.start',
            tool_name:    tool_name_val,
            runner_class: runner_class_str,
            function:     function_name,
            params:       LoggingSupport.summarize_params(params)
          )
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
            response = ::MCP::Tool::Response.new([{ type: 'text', text: text }])
            LoggingSupport.info(
              'catalog.tool_call.complete',
              tool_name:    tool_name_val,
              runner_class: runner_class_str,
              function:     function_name,
              result:       LoggingSupport.summarize_result(response)
            )
            response
          end
        rescue StandardError => e
          handle_exception(e, level: :warn, operation: 'legion.mcp.catalog_dispatcher.call')
          LoggingSupport.warn(
            'catalog.tool_call.failed',
            tool_name:    tool_name_val,
            runner_class: runner_class_str,
            function:     function_name,
            error:        e.message
          )
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
          handle_exception(e, level: :debug, operation: 'legion.mcp.catalog_dispatcher.generate_tools_from_catalog')
          log.debug("CatalogDispatcher: skipping #{cap}: #{e.message}")
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
