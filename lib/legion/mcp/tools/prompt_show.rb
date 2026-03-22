# frozen_string_literal: true

module Legion
  module MCP
    module Tools
      class PromptShow < ::MCP::Tool
        tool_name 'legion.prompt_show'
        description 'Retrieve a prompt template by name, optionally pinned to a specific version or tag.'

        input_schema(
          properties: {
            name:    { type: 'string', description: 'Name of the prompt template' },
            version: { type: 'integer', description: 'Specific version number to fetch (default: latest)' },
            tag:     { type: 'string', description: 'Named tag to resolve (e.g. "stable", "production")' }
          },
          required:   ['name']
        )

        class << self
          def call(name:, version: nil, tag: nil)
            return error_response('lex-prompt is not loaded') unless extension_loaded?('prompt')

            require 'legion/extensions/prompt/client'
            client = Legion::Extensions::Prompt::Client.new(db: db)
            result = client.get_prompt(name: name, version: version, tag: tag)
            text_response(result)
          rescue StandardError => e
            Legion::Logging.warn("PromptShow#call failed: #{e.message}") if defined?(Legion::Logging)
            error_response("Failed to fetch prompt: #{e.message}")
          end

          private

          def extension_loaded?(name)
            require "legion/extensions/#{name}"
            true
          rescue LoadError => e
            Legion::Logging.debug("PromptShow#extension_loaded? #{name} not available: #{e.message}") if defined?(Legion::Logging)
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
