# frozen_string_literal: true

module Legion
  module MCP
    module Tools
      class StructuralIndexTool < ::MCP::Tool
        tool_name 'legion.structural_index'
        description 'Return the precomputed structural index of all extensions, runners, actors, and tools. ' \
                    'Filter by extension name or type (tools, extensions, runners, actors).'

        input_schema(
          properties: {
            extension: {
              type:        'string',
              description: 'Filter by extension name (partial match)'
            },
            type:      {
              type:        'string',
              description: 'Filter by type: tools, extensions, runners, actors',
              enum:        %w[tools extensions runners actors]
            },
            refresh:   {
              type:        'boolean',
              description: 'Force rebuild of the index (ignores cache)'
            }
          }
        )

        class << self
          def call(extension: nil, type: nil, refresh: nil)
            index = if refresh
                      StructuralIndex.save_cache(StructuralIndex.build)
                    else
                      StructuralIndex.load_or_build
                    end

            result = StructuralIndex.filter(index, extension: extension, type: type)
            text_response(result)
          rescue StandardError => e
            Legion::Logging.warn("StructuralIndexTool#call failed: #{e.message}") if defined?(Legion::Logging)
            error_response("Failed: #{e.message}")
          end

          private

          def text_response(data)
            ::MCP::Tool::Response.new([{ type: 'text', text: Legion::JSON.dump(data) }])
          end

          def error_response(msg)
            ::MCP::Tool::Response.new([{ type: 'text', text: Legion::JSON.dump({ error: msg }) }], error: true)
          end
        end
      end
    end
  end
end
