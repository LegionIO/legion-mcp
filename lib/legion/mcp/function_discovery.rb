# frozen_string_literal: true

module Legion
  module MCP
    module FunctionDiscovery
      module_function

      def discover_and_register
        return unless defined?(Legion::Extensions)

        extensions = Legion::Extensions.instance_variable_get(:@extensions) || []
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

        class_expose = runner_module.class.respond_to?(:expose_as_mcp_tool) ? runner_module.class.expose_as_mcp_tool : nil
        global_expose = if defined?(Legion::Settings)
                          Legion::Settings.dig(:mcp, :auto_expose_runners) || false
                        else
                          false
                        end
        prefix = runner_module.class.respond_to?(:mcp_tool_prefix) ? runner_module.class.mcp_tool_prefix : nil

        functions.each do |func_name, meta|
          next unless should_expose?(meta, class_expose, global_expose)
          next unless deps_satisfied?(meta[:requires])

          tool_class = build_tool_class(
            name:          derive_tool_name(func_name, prefix),
            description:   meta[:desc] || "Auto-discovered: #{func_name}",
            input_schema:  meta[:options] || { properties: {} },
            runner_module: runner_module,
            function_name: func_name
          )

          Server.register_tool(tool_class)
        end
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
          parts = dep.split('::')
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
            result = if runner_ref.respond_to?(func_ref)
                       runner_ref.public_send(func_ref, **params)
                     else
                       { success: false, error: "function #{func_ref} not found" }
                     end

            text = defined?(Legion::JSON) ? Legion::JSON.dump(result) : result.to_s
            ::MCP::Tool::Response.new([{ type: 'text', text: text }])
          end
        end
      end
    end
  end
end
