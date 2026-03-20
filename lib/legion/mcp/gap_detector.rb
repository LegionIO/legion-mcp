# frozen_string_literal: true

require 'digest'

module Legion
  module MCP
    module GapDetector
      FREQUENCY_THRESHOLD = 5
      CHAIN_THRESHOLD = 3

      module_function

      def analyze
        gaps = []
        gaps.concat(detect_frequent_intents)
        gaps.concat(detect_repeated_chains)
        gaps
      end

      def detect_frequent_intents
        intents = Observer.recent_intents(Observer::INTENT_BUFFER_MAX)
        grouped = intents.group_by { |i| i[:matched_tool] }

        grouped.filter_map do |tool, occurrences|
          next if occurrences.size < FREQUENCY_THRESHOLD
          next if PatternStore.pattern_exists?(Digest::SHA256.hexdigest(tool.to_s))

          { type: :frequent_intent, tool: tool, count: occurrences.size,
            sample_intents: occurrences.last(3).map { |o| o[:intent] } }
        end
      end

      def detect_repeated_chains
        recent = Observer.recent(Observer::RING_BUFFER_MAX)
        chains = {}
        recent.each_cons(2) do |a, b|
          key = "#{a[:tool_name]}->#{b[:tool_name]}"
          chains[key] = (chains[key] || 0) + 1
        end

        chains.filter_map do |chain, count|
          next if count < CHAIN_THRESHOLD
          { type: :repeated_chain, chain: chain.split('->'), count: count }
        end
      end

      def reset!
        # No persistent state to clear — analysis reads from Observer
      end
    end
  end
end
