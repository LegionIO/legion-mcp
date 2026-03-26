# frozen_string_literal: true

module Legion
  module MCP
    module Tools
      class KnowledgeContext < ::MCP::Tool
        tool_name 'legion.knowledge_context'
        description 'Retrieve knowledge relevant to the current task. Call this when you need context about ' \
                    'the codebase, architecture, past decisions, or known gotchas.'

        input_schema(
          properties: {
            question: { type: 'string',  description: 'What do you need to know?' },
            scope:    { type: 'string',  description: 'Knowledge scope: local (this node), global (shared), all (merged). Default: all',
                        enum: %w[local global all] },
            top_k:    { type: 'integer', description: 'Number of source chunks to retrieve (default 5)' }
          },
          required:   %w[question]
        )

        class << self
          def call(question:, scope: 'all', top_k: 5)
            return error_response('lex-knowledge is not available') unless knowledge_available?(scope)

            result = case scope
                     when 'local'  then query_local(question: question, top_k: top_k)
                     when 'global' then query_global(question: question, top_k: top_k)
                     else               query_all(question: question, top_k: top_k)
                     end

            text_response(result)
          rescue StandardError => e
            Legion::Logging.warn("KnowledgeContext#call failed: #{e.message}") if defined?(Legion::Logging)
            error_response("Knowledge context failed: #{e.message}")
          end

          private

          def knowledge_available?(scope = 'all')
            return defined?(Legion::Apollo::Local) if scope == 'local'

            defined?(Legion::Extensions::Knowledge::Runners::Query)
          end

          def query_global(question:, top_k:)
            result = Legion::Extensions::Knowledge::Runners::Query.query(
              question:   question,
              top_k:      top_k,
              synthesize: true
            )
            result.merge(scope: 'global')
          end

          def query_local(question:, top_k:)
            if defined?(Legion::Apollo::Local)
              result = Legion::Apollo::Local.query(question: question, top_k: top_k)
              result.merge(scope: 'local')
            else
              Legion::Logging.warn('KnowledgeContext: Apollo::Local not available, falling back to global') if defined?(Legion::Logging)
              query_global(question: question, top_k: top_k)
            end
          end

          def query_all(question:, top_k:)
            global = query_global(question: question, top_k: top_k)
            return global unless defined?(Legion::Apollo::Local)

            local = Legion::Apollo::Local.query(question: question, top_k: top_k)
            merge_results(global, local)
          end

          def merge_results(global, local)
            global_sources = Array(global[:sources] || global['sources'])
            local_sources  = Array(local[:sources]  || local['sources'])

            seen        = {}
            deduped     = []
            (local_sources + global_sources).each do |src|
              key = src[:content_hash] || src['content_hash'] || src[:content] || src['content']
              next if seen[key]

              seen[key] = true
              deduped << src
            end

            global_answer = global[:answer] || global['answer']
            local_answer  = local[:answer]  || local['answer']
            answer        = global_answer.nil? || global_answer.to_s.empty? ? local_answer : global_answer
            { answer: answer, sources: deduped, scope: 'all' }
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
