# frozen_string_literal: true

module Legion
  module MCP
    module Tools
      class EvalRun < ::MCP::Tool
        tool_name 'legion.eval_run'
        description 'Run an evaluator against a single input/output pair and return pass/fail with score.'

        input_schema(
          properties: {
            evaluator_name: { type: 'string', description: 'Name of the evaluator template to use' },
            input:          { type: 'string', description: 'The original input/prompt given to the model' },
            output:         { type: 'string', description: 'The model output to evaluate' },
            expected:       { type: 'string', description: 'Optional expected/reference output for comparison' }
          },
          required:   %w[evaluator_name input output]
        )

        class << self
          include Legion::Logging::Helper

          def call(evaluator_name:, input:, output:, expected: nil)
            log.info('Starting legion.mcp.tools.eval_run.call')
            return error_response('lex-eval is not loaded') unless extension_loaded?('eval')

            require 'legion/extensions/eval/client'
            client = Legion::Extensions::Eval::Client.new(db: db)
            inputs = [{ input: input, output: output, expected: expected }.compact]
            result = client.run_evaluation(evaluator_name: evaluator_name, inputs: inputs)
            text_response(result)
          rescue StandardError => e
            handle_exception(e, level: :warn, operation: 'legion.mcp.tools.eval_run.call')
            log.warn("EvalRun#call failed: #{e.message}")
            error_response("Failed to run evaluation: #{e.message}")
          end

          private

          def extension_loaded?(name)
            require "legion/extensions/#{name}"
            true
          rescue LoadError => e
            handle_exception(e, level: :debug, operation: 'legion.mcp.tools.eval_run.extension_loaded?')
            log.debug("EvalRun#extension_loaded? #{name} not available: #{e.message}")
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
