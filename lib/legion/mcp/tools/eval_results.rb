# frozen_string_literal: true

module Legion
  module MCP
    module Tools
      class EvalResults < ::MCP::Tool
        tool_name 'legion.eval_results'
        description 'Retrieve stored results for a named experiment from the dataset experiment store.'

        input_schema(
          properties: {
            experiment_name: { type: 'string', description: 'Name of the experiment to retrieve results for' }
          },
          required:   ['experiment_name']
        )

        class << self
          def call(experiment_name:)
            return error_response('lex-dataset is not loaded') unless extension_loaded?('dataset')

            require 'legion/extensions/dataset/client'
            client = Legion::Extensions::Dataset::Client.new(db: db)
            result = fetch_experiment(client, experiment_name)
            text_response(result)
          rescue StandardError => e
            error_response("Failed to fetch eval results: #{e.message}")
          end

          private

          def fetch_experiment(client, name)
            db_handle = client.instance_variable_get(:@db)
            return { error: 'database_unavailable' } unless db_handle

            exp = db_handle[:experiments].where(name: name).first
            return { error: 'not_found' } unless exp

            rows = db_handle[:experiment_results]
                   .where(experiment_id: exp[:id])
                   .order(:row_index)
                   .all
                   .map { |r| { row_index: r[:row_index], passed: r[:passed], latency_ms: r[:latency_ms] } }

            summary = begin
              ::JSON.parse(exp[:summary], symbolize_names: true)
            rescue StandardError
              {}
            end

            { experiment_id: exp[:id], name: exp[:name], status: exp[:status],
              created_at: exp[:created_at], completed_at: exp[:completed_at],
              summary: summary, rows: rows }
          end

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
