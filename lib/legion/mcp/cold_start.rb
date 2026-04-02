# frozen_string_literal: true

require_relative 'pattern_store'
require_relative 'pattern_exchange'

module Legion
  module MCP
    module ColdStart
      extend Legion::Logging::Helper
      module_function

      def load_community_patterns(path: nil)
        log.info("Starting legion.mcp.cold_start.load_community_patterns")
        return { skipped: true, reason: 'store not empty' } unless PatternStore.empty?

        path ||= configured_path
        return { skipped: true, reason: 'no path configured' } unless path

        PatternExchange.import_from_file(path, trust_level: :community)
      rescue StandardError => e
        handle_exception(e, level: :error, operation: "legion.mcp.cold_start.load_community_patterns")
        log.error("ColdStart#load_community_patterns failed: #{e.message}")
        { error: e.message, imported: 0 }
      end

      def configured_path
        return nil unless defined?(Legion::Settings)

        Legion::Settings.dig(:mcp, :cold_start, :patterns_path)
      rescue StandardError => e
        handle_exception(e, level: :warn, operation: "legion.mcp.cold_start.configured_path")
        log.warn("ColdStart#configured_path failed: #{e.message}")
        nil
      end
    end
  end
end
