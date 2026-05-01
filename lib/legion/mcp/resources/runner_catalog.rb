# frozen_string_literal: true

module Legion
  module MCP
    module Resources
      module RunnerCatalog
        RESOURCE = ::MCP::Resource.new(
          uri:         'legion://runners',
          name:        'runner-catalog',
          description: 'All available extension.runner.function paths in this Legion instance.',
          mime_type:   'application/json'
        )

        class << self
          include Legion::Logging::Helper

          def register(server)
            log.debug('[mcp][runner_catalog] action=register')
            server.resources << RESOURCE

            server.resources_read_handler do |params|
              if params[:uri] == 'legion://runners'
                [{ uri: 'legion://runners', mimeType: 'application/json', text: catalog_json }]
              elsif params[:uri]&.start_with?('legion://extensions/')
                ExtensionInfo.read(params[:uri])
              else
                []
              end
            end
          end

          private

          def catalog_json
            return catalog_from_settings_extensions if settings_extensions_runners_available?

            return Legion::JSON.dump({ error: 'legion-data is not connected' }) unless data_connected?

            extensions = Legion::Data::Model::Extension.all
            catalog = extensions.map do |ext|
              runners = Legion::Data::Model::Runner.where(extension_id: ext.values[:id]).all
              {
                extension: ext.values[:name],
                runners:   runners.map do |r|
                  functions = Legion::Data::Model::Function.where(runner_id: r.values[:id]).all
                  {
                    runner:    r.values[:namespace],
                    functions: functions.map { |f| f.values[:name] }
                  }
                end
              }
            end

            Legion::JSON.dump(catalog)
          rescue StandardError => e
            handle_exception(e, level: :warn, operation: 'legion.mcp.resources.runner_catalog.catalog_json')
            Legion::JSON.dump({ error: "Failed to build catalog: #{e.message}" })
          end

          def settings_extensions_runners_available?
            Legion::Settings::Extensions.respond_to?(:runners) &&
              Legion::Settings::Extensions.runners.any?
          end

          def catalog_from_settings_extensions
            runners = Legion::Settings::Extensions.runners
            catalog = runners.map do |runner_entry|
              {
                name:      runner_entry[:name],
                extension: runner_entry[:extension],
                function:  runner_entry[:function],
                exposed:   runner_entry[:exposed]
              }
            end
            Legion::JSON.dump(catalog)
          rescue StandardError => e
            handle_exception(e, level: :warn, operation: 'legion.mcp.resources.runner_catalog.catalog_from_settings_extensions')
            Legion::JSON.dump({ error: "Failed to build catalog from settings: #{e.message}" })
          end

          def data_connected?
            Legion::Settings[:data][:connected]
          rescue StandardError => e
            handle_exception(e, level: :warn, operation: 'legion.mcp.resources.runner_catalog.data_connected?')
            false
          end
        end
      end
    end
  end
end
