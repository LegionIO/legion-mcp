# frozen_string_literal: true

return unless defined?(Legion::Extensions::Actors::Every)

module Legion
  module MCP
    module Actor
      class SelfGenerateCycle < Legion::Extensions::Actors::Every
        include Legion::Logging::Helper

        def runner_class    = self.class
        def runner_function = 'action'
        def check_subtask?  = false
        def generate_task?  = false

        def time
          if defined?(Legion::Settings) && !Legion::Settings[:codegen].nil?
            Legion::Settings.dig(:codegen, :self_generate, :cycle_interval) || 300
          else
            300
          end
        rescue StandardError => e
          handle_exception(e, level: :warn, operation: 'legion.mcp.actors.self_generate_cycle.time')
          log.warn(e.message)
          300
        end

        def enabled?
          SelfGenerate.enabled?
        rescue StandardError => e
          handle_exception(e, level: :warn, operation: 'legion.mcp.actors.self_generate_cycle.enabled?')
          log.warn(e.message)
          false
        end

        def action(_payload = nil)
          SelfGenerate.run_cycle
        end

      end
    end
  end
end
