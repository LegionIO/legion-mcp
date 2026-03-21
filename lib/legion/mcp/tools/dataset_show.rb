# frozen_string_literal: true

module Legion
  module MCP
    module Tools
      class DatasetShow < ::MCP::Tool
        tool_name 'legion.dataset_show'
        description 'Retrieve a dataset by name including all rows, optionally pinned to a specific version.'

        input_schema(
          properties: {
            name:    { type: 'string', description: 'Name of the dataset' },
            version: { type: 'integer', description: 'Specific version to fetch (default: latest)' }
          },
          required:   ['name']
        )

        class << self
          def call(name:, version: nil)
            return error_response('lex-dataset is not loaded') unless extension_loaded?('dataset')

            require 'legion/extensions/dataset/client'
            client = Legion::Extensions::Dataset::Client.new(db: db)
            result = client.get_dataset(name: name, version: version)
            text_response(result)
          rescue StandardError => e
            error_response("Failed to fetch dataset: #{e.message}")
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
