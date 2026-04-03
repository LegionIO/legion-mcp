# frozen_string_literal: true

module Legion
  module MCP
    module Tools
      class DiscoverTools < ::MCP::Tool
        tool_name 'legion.tools'
        description 'Discover available Legion tools by category or intent. Returns compressed definitions to reduce context. ' \
                    'Use tool_names with schema: true to load full schemas for deferred tools.'

        input_schema(
          properties: {
            category:   {
              type:        'string',
              description: 'Tool category: tasks, chains, relationships, extensions, schedules, workers, rbac, status, describe'
            },
            intent:     {
              type:        'string',
              description: 'Describe what you want to do and relevant tools will be ranked'
            },
            tool_names: {
              type:        'array',
              items:       { type: 'string' },
              description: 'Specific tool names to retrieve full schemas for (e.g., ["legion.ask_peer", "legion.list_peers"])'
            },
            schema:     {
              type:        'boolean',
              description: 'When true with tool_names, returns full JSON schemas for the specified tools'
            }
          }
        )

        class << self
          include Legion::Logging::Helper

          def call(category: nil, intent: nil, tool_names: nil, schema: nil)
            log.info('Starting legion.mcp.tools.discover_tools.call')
            if tool_names && schema
              resolve_schemas(tool_names)
            elsif category
              lookup_category(category)
            elsif intent
              results = ContextCompiler.match_tools(intent, limit: 5)
              text_response({ matched_tools: results })
            else
              text_response(ContextCompiler.compressed_catalog)
            end
          rescue StandardError => e
            handle_exception(e, level: :warn, operation: 'legion.mcp.tools.discover_tools.call')
            log.warn("DiscoverTools#call failed: #{e.message}")
            error_response("Failed: #{e.message}")
          end

          private

          def resolve_schemas(tool_names)
            schemas = DeferredRegistry.resolve_schemas(tool_names, Server.tool_registry)
            if schemas.empty?
              error_response("No tools found matching: #{tool_names.join(', ')}")
            else
              text_response({ schemas: schemas })
            end
          end

          def lookup_category(category)
            result = ContextCompiler.category_tools(category.to_sym)
            return error_response("Unknown category: #{category}") if result.nil?

            text_response(result)
          end

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
