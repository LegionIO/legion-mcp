# frozen_string_literal: true

module Legion
  module MCP
    module Tools
      class PromptList < ::MCP::Tool
        tool_name 'legion.prompt_list'
        description 'List all stored LLM prompt templates with their latest version and metadata.'

        input_schema(properties: {})

        class << self
          def call
            return error_response('lex-prompt is not loaded') unless extension_loaded?('prompt')

            require 'legion/extensions/prompt/client'
            client = Legion::Extensions::Prompt::Client.new(db: db)
            result = client.list_prompts
            text_response(result)
          rescue StandardError => e
            error_response("Failed to list prompts: #{e.message}")
          end

          private

          def extension_loaded?(name)
            require "legion/extensions/#{name}"
            true
          rescue LoadError
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
