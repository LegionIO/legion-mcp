# frozen_string_literal: true

module Legion
  module MCP
    module Tools
      class DatasetList < ::MCP::Tool
        tool_name 'legion.dataset_list'
        description 'List all stored datasets with their latest version and row counts.'

        input_schema(properties: {})

        class << self
          def call
            return error_response('lex-dataset is not loaded') unless extension_loaded?('dataset')

            require 'legion/extensions/dataset/client'
            client = Legion::Extensions::Dataset::Client.new(db: db)
            result = client.list_datasets
            text_response(result)
          rescue StandardError => e
            error_response("Failed to list datasets: #{e.message}")
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
