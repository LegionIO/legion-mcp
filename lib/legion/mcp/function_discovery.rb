# frozen_string_literal: true

module Legion
  module MCP
    module FunctionDiscovery
      extend Legion::Logging::Helper

      module_function

      def discover_and_register # rubocop:disable Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
        return if @discovery_fired

        @discovery_fired = true
        log.debug('[mcp][discovery] action=discover_and_register')

        # Prefer centralized registry when available and populated
        if settings_extensions_available?
          log.debug('[mcp][discovery] action=discover_and_register source=settings_extensions')
          register_from_settings_extensions
          return
        end

        if defined?(Legion::Tools::Discovery) && Legion::Tools::Discovery.respond_to?(:discover_and_register)
          log.debug('[mcp][discovery] action=discover_and_register source=tools_discovery')
          Legion::Tools::Discovery.discover_and_register
          return
        end

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
          handle_exception(e, level: :debug, operation: 'legion.mcp.function_discovery.discover_and_register')
        end
      end

      def reset_discovery!
        @discovery_fired = false
      end

      def build_tools_from_runner(runner_module)
        return unless runner_module.respond_to?(:settings) && runner_module.settings.is_a?(Hash)

        functions = runner_module.settings[:functions]
        return if functions.nil? || functions.empty?

        log.debug("[mcp][discovery] action=build_tools_from_runner runner=#{runner_module} functions=#{functions.size}")
        opts = runner_expose_opts(runner_module)
        functions.each { |func_name, meta| register_function(runner_module, func_name, meta, opts) }
      end

      def runner_expose_opts(_runner_module)
        global_expose = Legion::Settings.dig(:mcp, :auto_expose_runners) || false
        { class_expose: nil, global_expose: global_expose, prefix: nil }
      end

      def register_function(runner_module, func_name, meta, opts)
        defn = definition_for(runner_module, func_name)
        exposed = resolve_exposed(defn, meta, opts)
        unless exposed
          log.debug("[mcp][discovery] action=register_function func=#{func_name} skipped=not_exposed")
          return
        end

        requires = defn&.dig(:requires)&.map(&:to_s) || meta[:requires]
        unless deps_satisfied?(requires)
          log.debug("[mcp][discovery] action=register_function func=#{func_name} skipped=deps_unsatisfied")
          return
        end

        log.debug("[mcp][discovery] action=register_function func=#{func_name} runner=#{runner_module}")
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
        log.debug("[mcp][discovery] action=build_tool_class tool=#{opts[:name]} " \
                  "category=#{opts[:mcp_category]} tier=#{opts[:mcp_tier]}")
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
                handle_exception(e, level: :warn, operation: 'legion.mcp.function_discovery.call')
                error = true
                { error: e.message }
              end
            else
              error = true
              { error: "function #{func_ref} not found" }
            end
          text = Legion::JSON.dump(result)
          ::MCP::Tool::Response.new([{ type: 'text', text: text }], error: error)
        end
      end

      # Returns true when Settings::Extensions is defined and has tools registered.
      def settings_extensions_available?
        Legion::Settings::Extensions.respond_to?(:tools) &&
          Legion::Settings::Extensions.tools.any?
      end

      # Registers tools from the centralized Settings::Extensions registry.
      # Each tool entry is adapted into an MCP tool class via ToolAdapter.
      def register_from_settings_extensions
        entries = Legion::Settings::Extensions.tools
        log.debug("[mcp][discovery] action=register_from_settings_extensions entries=#{entries.size}")
        entries.each do |tool_entry|
          next if Server.tool_registry.any? { |tc| tc.tool_name == tool_entry[:name] }

          adapter = ToolAdapter.from_registry_entry(tool_entry)
          Server.register_tool(adapter) if adapter
        rescue StandardError => e
          handle_exception(e, level: :debug, operation: 'legion.mcp.function_discovery.register_from_settings_extensions')
        end
      end
    end
  end
end
