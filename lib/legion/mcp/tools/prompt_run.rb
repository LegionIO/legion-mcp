# frozen_string_literal: true

module Legion
  module MCP
    module Tools
      class PromptRun < ::MCP::Tool
        tool_name 'legion.prompt_run'
        description 'Render a prompt template with variable substitution and return the final text.'

        input_schema(
          properties: {
            name:      { type: 'string', description: 'Name of the prompt template to render' },
            variables: {
              type:                 'object',
              description:          'Key/value pairs to substitute into the ERB template',
              additionalProperties: true
            },
            version:   { type: 'integer', description: 'Specific version to render (default: latest)' }
          },
          required:   ['name']
        )

        class << self
          include Legion::Logging::Helper

          def call(name:, variables: {}, version: nil)
            log.info('Starting legion.mcp.tools.prompt_run.call')
            return error_response('lex-prompt is not loaded') unless extension_loaded?('prompt')

            require 'legion/extensions/prompt/client'
            client = Legion::Extensions::Prompt::Client.new(db: db)
            result = client.render_prompt(name: name, variables: variables, version: version)
            text_response(result)
          rescue StandardError => e
            handle_exception(e, level: :warn, operation: 'legion.mcp.tools.prompt_run.call')
            log.warn("PromptRun#call failed: #{e.message}")
            error_response("Failed to render prompt: #{e.message}")
          end

          private

          def extension_loaded?(name)
            require "legion/extensions/#{name}"
            true
          rescue LoadError => e
            handle_exception(e, level: :debug, operation: 'legion.mcp.tools.prompt_run.extension_loaded?')
            log.debug("PromptRun#extension_loaded? #{name} not available: #{e.message}")
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
