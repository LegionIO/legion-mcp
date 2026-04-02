# frozen_string_literal: true

module Legion
  module MCP
    module Tools
      class EvalList < ::MCP::Tool
        tool_name 'legion.eval_list'
        description 'List all available evaluator templates (LLM-as-judge and code-based).'

        input_schema(properties: {})

        class << self
          include Legion::Logging::Helper
          def call
            log.info("Starting legion.mcp.tools.eval_list.call")
            return error_response('lex-eval is not loaded') unless extension_loaded?('eval')

            require 'legion/extensions/eval/client'
            client = Legion::Extensions::Eval::Client.new(db: db)
            result = client.list_evaluators
            text_response(result)
          rescue StandardError => e
            handle_exception(e, level: :warn, operation: "legion.mcp.tools.eval_list.call")
            log.warn("EvalList#call failed: #{e.message}")
            error_response("Failed to list evaluators: #{e.message}")
          end

          private

          def extension_loaded?(name)
            require "legion/extensions/#{name}"
            true
          rescue LoadError => e
            handle_exception(e, level: :debug, operation: "legion.mcp.tools.eval_list.extension_loaded?")
            log.debug("EvalList#extension_loaded? #{name} not available: #{e.message}")
            false
          end

          def db
            Legion::Data.db
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
