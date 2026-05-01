# frozen_string_literal: true

require 'digest'

module Legion
  module MCP
    module GapDetector
      extend Legion::Logging::Helper

      GAP_INTENT_THRESHOLD = 5
      FAILURE_RATE_THRESHOLD = 0.4
      STALE_CANDIDATE_HOURS = 24
      MAX_GAPS              = 20

      module_function

      def detect_gaps
        log.debug('[mcp][gap_detector] action=detect_gaps')
        gaps = []
        gaps.concat(detect_unmatched_intents)
        gaps.concat(detect_high_failure_tools)
        gaps.concat(detect_stale_candidates)

        result = gaps.uniq { |g| g[:id] }.first(MAX_GAPS)
        log.debug("[mcp][gap_detector] action=detect_gaps.complete total=#{result.size}")
        result
      end

      def detect_unmatched_intents
        return [] unless defined?(Observer)

        recent = Observer.recent_intents(200)
        unmatched = recent.select { |r| r[:matched_tool].nil? || r[:matched_tool] == 'none' }

        grouped = unmatched.group_by { |r| normalize_intent(r[:intent]) }

        grouped.filter_map do |intent_text, occurrences|
          next if occurrences.size < GAP_INTENT_THRESHOLD

          {
            id:          "unmatched:#{Digest::SHA256.hexdigest(intent_text)[0, 12]}",
            type:        :unmatched_intent,
            intent:      intent_text,
            occurrences: occurrences.size,
            first_seen:  occurrences.first[:recorded_at],
            last_seen:   occurrences.last[:recorded_at],
            priority:    calculate_priority(occurrences.size, :unmatched)
          }
        end
      end

      def detect_high_failure_tools
        return [] unless defined?(Observer)

        stats = Observer.all_tool_stats
        stats.filter_map do |tool_name, tool_stat|
          next unless tool_stat
          next if tool_stat[:call_count] < 5

          failure_rate = tool_stat[:failure_count].to_f / tool_stat[:call_count]
          next if failure_rate < FAILURE_RATE_THRESHOLD

          {
            id:            "failing:#{tool_name}",
            type:          :high_failure_tool,
            tool_name:     tool_name,
            failure_rate:  failure_rate.round(4),
            call_count:    tool_stat[:call_count],
            failure_count: tool_stat[:failure_count],
            last_error:    tool_stat[:last_error],
            priority:      calculate_priority(tool_stat[:failure_count], :failure)
          }
        end
      end

      def detect_stale_candidates
        return [] unless defined?(Patterns::Store)

        candidates = Patterns::Store.candidates

        candidates.filter_map do |intent_hash, entry|
          next if entry[:count] < 2

          {
            id:                "stale:#{intent_hash[0, 12]}",
            type:              :stale_candidate,
            intent_hash:       intent_hash,
            intent_text:       entry[:intent_text],
            observation_count: entry[:count],
            tool_chain:        entry[:tool_chain],
            priority:          calculate_priority(entry[:count], :stale)
          }
        end
      end

      def normalize_intent(text)
        text.to_s.strip.downcase.gsub(/\s+/, ' ')
      end

      def calculate_priority(count, type)
        base = case type
               when :unmatched then 0.8
               when :failure   then 0.6
               when :stale     then 0.4
               else 0.3
               end
        (base + [count * 0.02, 0.2].min).clamp(0.0, 1.0).round(4)
      end
    end
  end
end
