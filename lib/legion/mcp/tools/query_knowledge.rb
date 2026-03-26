# frozen_string_literal: true

module Legion
  module MCP
    module Tools
      class QueryKnowledge < ::MCP::Tool
        tool_name 'legion.query_knowledge'
        description 'Search the document knowledge base. Returns a synthesized answer and ranked source chunks.'

        input_schema(
          properties: {
            question:   { type: 'string',  description: 'The question or search query' },
            top_k:      { type: 'integer', description: 'Number of source chunks to retrieve (default 5)' },
            synthesize: { type: 'boolean', description: 'Whether to synthesize an LLM answer (default true)' }
          },
          required:   %w[question]
        )

        class << self
          def call(question:, top_k: 5, synthesize: true)
            return error_response('lex-knowledge is not available') unless knowledge_available?

            result = Legion::Extensions::Knowledge::Runners::Query.query(
              question:   question,
              top_k:      top_k,
              synthesize: synthesize
            )
            text_response(result)
          rescue StandardError => e
            Legion::Logging.warn("QueryKnowledge#call failed: #{e.message}") if defined?(Legion::Logging)
            error_response("Knowledge query failed: #{e.message}")
          end

          private

          def knowledge_available?
            defined?(Legion::Extensions::Knowledge::Runners::Query)
          end

          def text_response(data)
            ::MCP::Tool::Response.new([{ type: 'text', text: Legion::JSON.dump({ **data }) }])
          end

          def error_response(msg)
            ::MCP::Tool::Response.new([{ type: 'text', text: Legion::JSON.dump({ error: msg }) }], error: true)
          end
        end
      end
    end
  end
end
