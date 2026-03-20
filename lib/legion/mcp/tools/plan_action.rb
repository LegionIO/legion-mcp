# frozen_string_literal: true

module Legion
  module MCP
    module Tools
      class PlanAction < ::MCP::Tool
        tool_name 'legion.plan'
        description 'Get a multi-step workflow plan for a complex goal. Returns ordered steps with tools and parameters.'

        input_schema(
          properties: {
            goal:    { type: 'string', description: 'Natural language description of the goal' },
            context: { type: 'object', description: 'Additional context', additionalProperties: true }
          },
          required:   ['goal']
        )

        class << self
          def call(goal:, context: {}) # rubocop:disable Lint/UnusedMethodArgument
            matched = ContextCompiler.match_tools(goal, limit: 10)
            steps = matched.map.with_index(1) do |tool, idx|
              { step: idx, tool: tool[:name], relevance: tool[:score].round(3) }
            end

            return text_response({ plan: nil, reason: 'no matching tools found for goal' }) if steps.empty?

            plan = { goal: goal, steps: steps, tool_count: steps.size }
            plan[:narrative] = generate_narrative(goal, steps) if llm_available?

            text_response(plan)
          rescue StandardError => e
            error_response("Plan failed: #{e.message}")
          end

          private

          def generate_narrative(goal, steps)
            tool_list = steps.map { |s| s[:tool] }.join(', ')
            Legion::LLM.ask("Create a brief execution plan for: #{goal}. Available tools: #{tool_list}")
          rescue StandardError
            nil
          end

          def llm_available?
            defined?(Legion::LLM) && Legion::LLM.started?
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
