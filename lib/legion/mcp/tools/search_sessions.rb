# frozen_string_literal: true

module Legion
  module MCP
    module Tools
      class SearchSessions < ::MCP::Tool
        tool_name 'legion.search_sessions'
        description 'Search across past conversation sessions by keyword or topic. Returns matching ' \
                    'sessions with context snippets sorted by relevance.'

        SESSIONS_DIR = File.expand_path('~/.legion/sessions')

        input_schema(
          properties: {
            query: {
              type:        'string',
              description: 'Search query — keywords or topic to find in past sessions'
            },
            limit: {
              type:        'integer',
              description: 'Maximum number of results to return (default 5)'
            }
          },
          required:   ['query']
        )

        class << self
          include Legion::Logging::Helper

          def call(query:, limit: 5)
            log.info('Starting legion.mcp.tools.search_sessions.call')
            return error_response('query cannot be empty') if query.to_s.strip.empty?

            results = search(query, limit: limit)
            text_response({ query: query, results: results, total: results.size })
          rescue StandardError => e
            handle_exception(e, level: :warn, operation: 'legion.mcp.tools.search_sessions.call')
            log.warn("SearchSessions#call failed: #{e.message}")
            error_response("Failed: #{e.message}")
          end

          private

          def search(query, limit: 5)
            sessions_dir = resolve_sessions_dir
            return [] unless sessions_dir && Dir.exist?(sessions_dir)

            pattern = query.downcase
            matches = Dir.glob(File.join(sessions_dir, '*.json')).filter_map do |path|
              match_session(path, pattern)
            rescue StandardError => e
              handle_exception(e, level: :debug, operation: 'legion.mcp.tools.search_sessions.search')
              nil
            end
            matches.sort_by { |r| -r[:matches] }.first(limit)
          end

          def match_session(path, pattern)
            data = Legion::JSON.load(File.read(path))
            messages = data[:messages] || data['messages'] || []
            matches = messages.count { |m| content_matches?(m, pattern) }
            return nil if matches.zero?

            first_match = messages.find { |m| content_matches?(m, pattern) }
            context = extract_context(first_match, pattern)

            {
              session: data[:name] || data['name'] || File.basename(path, '.json'),
              file:    File.basename(path),
              matches: matches,
              context: context
            }
          end

          def content_matches?(message, pattern)
            content = message[:content] || message['content']
            content.to_s.downcase.include?(pattern)
          end

          def extract_context(message, pattern)
            content = (message[:content] || message['content']).to_s
            idx = content.downcase.index(pattern)
            return content[0..200] unless idx

            start = [idx - 50, 0].max
            content[start, 200]
          end

          def resolve_sessions_dir
            custom = Legion::Settings.dig(:chat, :sessions_dir) if defined?(Legion::Settings)
            custom || SESSIONS_DIR
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
