# frozen_string_literal: true

require 'json'
require_relative 'pattern_schema'
require_relative 'pattern_store'

module Legion
  module MCP
    module PatternExchange
      extend Legion::Logging::Helper

      module_function

      def export_all(min_confidence: 0.5)
        PatternStore.patterns.filter_map do |_hash, pattern|
          next if (pattern[:confidence] || 0) < min_confidence

          PatternSchema.export(pattern)
        end
      end

      def import_all(patterns, trust_level: :community)
        log.debug("[mcp][pattern_exchange] action=import_all count=#{Array(patterns).size} trust_level=#{trust_level}")
        imported = 0
        skipped = 0

        Array(patterns).each do |external|
          next unless PatternSchema.validate_schema(external)

          internal = PatternSchema.import(external, trust_level: trust_level)
          if PatternStore.pattern_exists?(internal[:intent_hash])
            skipped += 1
            next
          end

          PatternStore.store(internal)
          imported += 1
        end

        { imported: imported, skipped: skipped }
      end

      def export_to_file(path, min_confidence: 0.5)
        log.debug("[mcp][pattern_exchange] action=export_to_file path=#{path} min_confidence=#{min_confidence}")
        data = export_all(min_confidence: min_confidence)
        File.write(path, ::JSON.pretty_generate(data))
        { exported: data.size, path: path }
      end

      def import_from_file(path, trust_level: :community)
        log.debug("[mcp][pattern_exchange] action=import_from_file path=#{path} trust_level=#{trust_level}")
        raw = File.read(path)
        patterns = ::JSON.parse(raw, symbolize_names: true)
        patterns = [patterns] if patterns.is_a?(Hash)
        import_all(patterns, trust_level: trust_level)
      rescue StandardError => e
        handle_exception(e, level: :error, operation: 'legion.mcp.pattern_exchange.import_from_file')
        { error: e.message, imported: 0 }
      end
    end
  end
end
