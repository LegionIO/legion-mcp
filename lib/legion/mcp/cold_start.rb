# frozen_string_literal: true

require_relative 'patterns/store'
require_relative 'patterns/exchange'

module Legion
  module MCP
    module ColdStart
      extend Legion::Logging::Helper

      module_function

      def load_community_patterns(path: nil)
        log.debug("[mcp][cold_start] action=load_community_patterns store_empty=#{Patterns::Store.empty?}")
        return { skipped: true, reason: 'store not empty' } unless Patterns::Store.empty?

        path ||= configured_path
        return { skipped: true, reason: 'no path configured' } unless path

        log.debug("[mcp][cold_start] action=load_community_patterns path=#{path}")

        Patterns::Exchange.import_from_file(path, trust_level: :community)
      rescue StandardError => e
        handle_exception(e, level: :error, operation: 'legion.mcp.cold_start.load_community_patterns')
        { error: e.message, imported: 0 }
      end

      def configured_path
        Legion::Settings.dig(:mcp, :cold_start, :patterns_path)
      rescue StandardError => e
        handle_exception(e, level: :warn, operation: 'legion.mcp.cold_start.configured_path')
        nil
      end
    end
  end
end
