# frozen_string_literal: true

require_relative 'logging_support'
require_relative 'tool_adapter'

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
            text = Legion::JSON.dump(result)
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
        return [] unless defined?(Legion::Settings::Extensions)
        return [] unless Legion::Settings::Extensions.respond_to?(:tools)

        Legion::Settings::Extensions.tools.filter_map do |tool_entry|
          ToolAdapter.from_registry_entry(tool_entry) if defined?(ToolAdapter) && ToolAdapter.respond_to?(:from_registry_entry)
        rescue StandardError => e
          handle_exception(e, level: :debug, operation: 'legion.mcp.catalog_dispatcher.generate_tools_from_catalog')
          nil
        end
      end
    end
  end
end
