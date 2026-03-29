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

      def runner_expose_opts(_runner_module)
        global_expose = defined?(Legion::Settings) ? (Legion::Settings.dig(:mcp, :auto_expose_runners) || false) : false
        { class_expose: nil, global_expose: global_expose, prefix: nil }
      end

      def register_function(runner_module, func_name, meta, opts)
        defn = definition_for(runner_module, func_name)
        return unless resolve_exposed(defn, meta, opts)

        requires = defn&.dig(:requires)&.map(&:to_s) || meta[:requires]
        return unless deps_satisfied?(requires)

        Server.register_tool(build_tool_class(build_tool_opts(runner_module, func_name, meta, opts, defn)))
      end

      def resolve_exposed(defn, meta, opts)
        if defn.nil?
          should_expose?(meta, opts[:class_expose], opts[:global_expose])
        else
          should_expose_from_definition?(defn, meta, opts[:class_expose], opts[:global_expose])
        end
      end

      def build_tool_opts(runner_module, func_name, meta, opts, defn)
        prefix = defn&.dig(:mcp_prefix) || opts[:prefix]
        {
          name:          derive_tool_name(func_name, prefix),
          description:   meta[:desc] || defn&.dig(:desc) || "Auto-discovered: #{func_name}",
          input_schema:  meta[:options] || { properties: {} },
          runner_module: runner_module,
          function_name: func_name,
          mcp_category:  defn&.dig(:mcp_category),
          mcp_tier:      defn&.dig(:mcp_tier)
        }
      end

      # Returns the definition hash for a method on a runner module, or nil if not available.
      def definition_for(runner_module, func_name)
        return nil unless runner_module.respond_to?(:definition_for)

        runner_module.definition_for(func_name)
      end

      # Exposure check when a definition is present.
      # definition[:mcp_exposed] takes highest precedence; falls back to legacy path.
      def should_expose_from_definition?(defn, func_meta, class_level, global_default)
        mcp_exposed = defn[:mcp_exposed]
        return mcp_exposed unless mcp_exposed.nil?

        should_expose?(func_meta, class_level, global_default)
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

      def build_tool_class(opts)
        runner_ref         = opts[:runner_module]
        func_ref           = opts[:function_name]
        tool_name_value    = opts[:name]
        description_value  = opts[:description]
        input_schema_value = opts[:input_schema]
        mcp_category_value = opts[:mcp_category]
        mcp_tier_value     = opts[:mcp_tier]
        klass = Class.new(::MCP::Tool) do
          tool_name tool_name_value
          description description_value
          input_schema(input_schema_value)
          define_singleton_method(:mcp_category) { mcp_category_value }
          define_singleton_method(:mcp_tier)     { mcp_tier_value }
        end
        wire_call_method(klass, runner_ref, func_ref)
        klass
      end

      def wire_call_method(klass, runner_ref, func_ref)
        klass.define_singleton_method(:call) do |**params|
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
