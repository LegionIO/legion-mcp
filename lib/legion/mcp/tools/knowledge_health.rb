# frozen_string_literal: true

module Legion
  module MCP
    module Tools
      class KnowledgeHealth < ::MCP::Tool
        tool_name 'legion.knowledge_health'
        description 'Get health report for the document knowledge base. Returns local, Apollo, and sync stats.'

        input_schema(
          properties: {
            path: { type: 'string', description: 'Corpus directory path (falls back to settings)' }
          }
        )

        class << self
          include Legion::Logging::Helper

          def call(path: nil)
            log.info('Starting legion.mcp.tools.knowledge_health.call')
            return error_response('lex-knowledge is not available') unless knowledge_available?

            resolved = resolve_path(path)
            return error_response('No corpus path configured') unless resolved

            result = Legion::Extensions::Knowledge::Runners::Maintenance.health(path: resolved)
            text_response(result)
          rescue StandardError => e
            handle_exception(e, level: :warn, operation: 'legion.mcp.tools.knowledge_health.call')
            log.warn("KnowledgeHealth#call failed: #{e.message}")
            error_response("Knowledge health failed: #{e.message}")
          end

          private

          def knowledge_available?
            defined?(Legion::Extensions::Knowledge::Runners::Maintenance)
          end

          def resolve_path(path)
            return path if path && !path.empty?
            return nil unless defined?(Legion::Settings)

            Legion::Settings.dig(:knowledge, :corpus_path)
          rescue StandardError => e
            handle_exception(e, level: :debug, operation: 'legion.mcp.tools.knowledge_health.resolve_path')
            nil
          end

          def text_response(data)
            ::MCP::Tool::Response.new([{ type: 'text', text: Legion::JSON.dump(data) }])
          end

          def error_response(msg)
            body = { error: msg }
            ::MCP::Tool::Response.new([{ type: 'text', text: Legion::JSON.dump(body) }], error: true)
          end
        end
      end
    end
  end
end
