# frozen_string_literal: true

# Shared stubs for Legion::Extensions::Capability and Catalog::Registry
# Used by MCP server specs that need Catalog integration
unless defined?(Legion::Extensions::Capability)
  module Legion
    module Extensions
      Capability = ::Data.define(
        :name, :extension, :runner, :function,
        :description, :parameters, :tags, :loaded_at
      ) do
        def self.from_runner(extension:, runner:, function:, description: nil, parameters: nil, tags: nil)
          canonical = "#{extension}:#{runner.to_s.gsub(/([A-Z])/, '_\1').sub(/^_/, '').downcase}:#{function}"
          new(
            name: canonical, extension: extension, runner: runner.to_s,
            function: function.to_s, description: description,
            parameters: parameters || {}, tags: Array(tags), loaded_at: Time.now
          )
        end

        def to_mcp_tool
          snake_runner = runner.gsub(/([A-Z])/, '_\1').sub(/^_/, '').downcase
          tool_name = "legion.#{extension.delete_prefix('lex-').tr('-', '_')}.#{snake_runner}.#{function}"
          properties = (parameters || {}).transform_values do |v|
            v.is_a?(Hash) ? v : { type: v.to_s }
          end
          {
            name: tool_name,
            description: description || "#{extension} #{runner}##{function}",
            input_schema: {
              type: 'object', properties: properties,
              required: parameters&.select { |_, v| v.is_a?(Hash) && v[:required] }&.keys&.map(&:to_s) || []
            }
          }
        end
      end
    end
  end
end

unless defined?(Legion::Extensions::Catalog::Registry) &&
       Legion::Extensions::Catalog::Registry.respond_to?(:find_by_mcp_name)
  module Legion
    module Extensions
      module Catalog
        module Registry
          @capabilities = []
          @by_name = {}
          @mutex = Mutex.new
          @on_change_callbacks = []

          module_function

          def register(capability)
            @mutex.synchronize do
              return if @by_name.key?(capability.name)

              @capabilities << capability
              @by_name[capability.name] = capability
            end
          end

          def unregister(name)
            @mutex.synchronize do
              cap = @by_name.delete(name)
              @capabilities.delete(cap) if cap
            end
          end

          def for_mcp
            @mutex.synchronize { @capabilities.dup }
          end

          def find_by_mcp_name(mcp_name)
            @mutex.synchronize do
              @capabilities.find { |cap| cap.to_mcp_tool[:name] == mcp_name }
            end
          end

          def on_change(&block)
            @mutex.synchronize { @on_change_callbacks << block }
          end

          def reset!
            @mutex.synchronize do
              @capabilities.clear
              @by_name.clear
              @on_change_callbacks.clear
            end
          end
        end
      end
    end
  end
end
