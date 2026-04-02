# frozen_string_literal: true

module Legion
  module MCP
    module Tools
      class RunTask < ::MCP::Tool
        tool_name 'legion.run_task'
        description 'Execute a Legion task using dot notation (e.g., "http.request.get"). Returns the task result.'

        input_schema(
          properties: {
            task:   {
              type:        'string',
              description: 'Dot notation path: extension.runner.function (e.g., "http.request.get")'
            },
            params: {
              type:                 'object',
              description:          'Parameters to pass to the task function',
              additionalProperties: true
            }
          },
          required:   ['task']
        )

        class << self
          include Legion::Logging::Helper
          def call(task:, params: {})
            log.info("Starting legion.mcp.tools.run_task.call")
            parts = task.split('.')
            return error_response("Invalid dot notation '#{task}'. Expected format: extension.runner.function") unless parts.length == 3

            ext_name, runner_name, function_name = parts
            runner_class = resolve_runner_class(ext_name, runner_name)

            result = Legion::Ingress.run(
              payload:       params,
              runner_class:  runner_class,
              function:      function_name.to_sym,
              source:        'mcp',
              check_subtask: true,
              generate_task: true
            )

            text_response(result)
          rescue NameError => e
            handle_exception(e, level: :warn, operation: "legion.mcp.tools.run_task.call")
            log.warn("RunTask#call runner not found: #{e.message}")
            error_response("Runner not found: #{e.message}")
          rescue StandardError => e
            handle_exception(e, level: :warn, operation: "legion.mcp.tools.run_task.call")
            log.warn("RunTask#call execution failed: #{e.message}")
            error_response("Task execution failed: #{e.message}")
          end

          private

          def resolve_runner_class(ext_name, runner_name)
            ext_part = ext_name.split('_').map(&:capitalize).join
            runner_part = runner_name.split('_').map(&:capitalize).join
            "Legion::Extensions::#{ext_part}::Runners::#{runner_part}"
          end

          def text_response(data)
            ::MCP::Tool::Response.new([{ type: 'text', text: Legion::JSON.dump(data) }])
          end

          def error_response(message)
            ::MCP::Tool::Response.new([{ type: 'text', text: Legion::JSON.dump({ error: message }) }], error: true)
          end
        end
      end
    end
  end
end
