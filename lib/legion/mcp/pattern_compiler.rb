# frozen_string_literal: true

module Legion
  module MCP
    module PatternCompiler
      module_function

      def compile_tool_definitions
        return [] unless defined?(Legion::MCP::Server::TOOL_CLASSES)

        Legion::MCP::Server::TOOL_CLASSES.map do |klass|
          name = klass.respond_to?(:tool_name) ? klass.tool_name : klass.name
          desc = klass.respond_to?(:description) ? klass.description : ''
          params = extract_params(klass)

          compressed = "#{name}(#{params.join(', ')}) -- #{desc.split('.').first}"
          { name: name, compressed: compressed.slice(0, 200), full_description: desc }
        end
      end

      def compile_workflows
        PatternStore.patterns.filter_map do |_hash, pattern|
          next if (pattern[:confidence] || 0) < 0.6

          {
            intent:     pattern[:intent_text],
            tools:      pattern[:tool_chain],
            confidence: pattern[:confidence],
            template:   pattern[:response_template]
          }
        end
      end

      def extract_params(klass)
        return [] unless klass.respond_to?(:input_schema)

        schema = klass.input_schema
        props = if schema.is_a?(Hash)
                  schema[:properties] || schema['properties']
                elsif schema.respond_to?(:to_h)
                  schema.to_h[:properties]
                end
        return [] unless props

        props.keys.map(&:to_s)
      rescue StandardError => e
        Legion::Logging.warn("PatternCompiler#extract_params failed: #{e.message}") if defined?(Legion::Logging)
        []
      end
    end
  end
end
