# frozen_string_literal: true

module Legion
  module MCP
    module FunctionDiscovery
      module_function

      def discover_and_register
        return unless defined?(Legion::Extensions)

        extensions =
          if Legion::Extensions.respond_to?(:extensions)
            Legion::Extensions.extensions || []
          else
            Legion::Extensions.instance_variable_get(:@extensions) || []
          end
        extensions.each do |ext|
          next unless ext.respond_to?(:runner_modules)

          ext.runner_modules.each { |runner_mod| build_tools_from_runner(runner_mod) }
        rescue StandardError => e
          Legion::Logging.debug("FunctionDiscovery: skipping #{ext}: #{e.message}") if defined?(Legion::Logging)
        end
      end

      def build_tools_from_runner(runner_module)
        return unless runner_module.respond_to?(:settings) && runner_module.settings.is_a?(Hash)

        functions = runner_module.settings[:functions]
        return if functions.nil? || functions.empty?

        opts = runner_expose_opts(runner_module)
        functions.each { |func_name, meta| register_function(runner_module, func_name, meta, opts) }
      end

      def runner_expose_opts(runner_module)
        class_expose = runner_module.respond_to?(:expose_as_mcp_tool) ? runner_module.expose_as_mcp_tool : nil
        global_expose = defined?(Legion::Settings) ? (Legion::Settings.dig(:mcp, :auto_expose_runners) || false) : false
        prefix = runner_module.respond_to?(:mcp_tool_prefix) ? runner_module.mcp_tool_prefix : nil
        { class_expose: class_expose, global_expose: global_expose, prefix: prefix }
      end

      def register_function(runner_module, func_name, meta, opts)
        return unless should_expose?(meta, opts[:class_expose], opts[:global_expose])
        return unless deps_satisfied?(meta[:requires])

        tool_class = build_tool_class(
          name:          derive_tool_name(func_name, opts[:prefix]),
          description:   meta[:desc] || "Auto-discovered: #{func_name}",
          input_schema:  meta[:options] || { properties: {} },
          runner_module: runner_module,
          function_name: func_name
        )

        Server.register_tool(tool_class)
      end

      def should_expose?(func_meta, class_level, global_default)
        return func_meta[:expose] unless func_meta[:expose].nil?
        return class_level unless class_level.nil?

        global_default || false
      end

      def derive_tool_name(func_name, prefix)
        base = prefix || 'legion.generated'
        "#{base}.#{func_name}"
      end

      def deps_satisfied?(deps)
        return true if deps.nil? || deps.empty?

        deps.all? do |dep|
          parts = dep.delete_prefix('::').split('::').reject(&:empty?)
          current = Object
          parts.all? do |part|
            if current.const_defined?(part, false)
              current = current.const_get(part, false)
              true
            else
              false
            end
          end
        end
      end

      def build_tool_class(name:, description:, input_schema:, runner_module:, function_name:)
        runner_ref = runner_module
        func_ref = function_name

        Class.new(::MCP::Tool) do
          tool_name name
          description description
          input_schema(input_schema)

          define_singleton_method(:call) do |**params|
            error = false

            result =
              if runner_ref.respond_to?(func_ref)
                begin
                  runner_ref.public_send(func_ref, **params)
                rescue StandardError => e
                  error = true
                  { error: e.message }
                end
              else
                error = true
                { error: "function #{func_ref} not found" }
              end

            text = defined?(Legion::JSON) ? Legion::JSON.dump(result) : result.to_s
            ::MCP::Tool::Response.new([{ type: 'text', text: text }], error: error)
          end
        end
      end
    end
  end
end
