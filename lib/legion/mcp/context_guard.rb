# frozen_string_literal: true

module Legion
  module MCP
    module ContextGuard
      DEFAULT_MAX_STALE_SECONDS      = 3600
      DEFAULT_RAPID_FIRE_THRESHOLD   = 5
      DEFAULT_RAPID_FIRE_WINDOW_SECS = 600
      DEFAULT_ANOMALY_MISS_THRESHOLD = 2

      extend Legion::Logging::Helper

      module_function

      def check(pattern, _params, _context)
        log.debug("[mcp][guard] action=check intent_hash=#{pattern[:intent_hash]&.[](0, 12)}")
        return staleness_failure(pattern) if stale?(pattern)
        return anomaly_failure(pattern) if anomalous?(pattern)
        return rapid_fire_failure(pattern) if rapid_fire?(pattern[:intent_hash])

        { passed: true }
      end

      def record_request(intent_hash)
        mutex.synchronize do
          requests[intent_hash] ||= []
          requests[intent_hash] << Time.now
        end
      end

      def reset!
        mutex.synchronize { requests.clear }
      end

      def stale?(pattern)
        last_hit = pattern[:last_hit_at]
        return false unless last_hit

        (Time.now - last_hit) > max_stale_seconds
      end

      def anomalous?(pattern)
        (pattern[:miss_count] || 0) >= anomaly_miss_threshold
      end

      def rapid_fire?(intent_hash)
        return false unless intent_hash

        window = Time.now - rapid_fire_window_seconds
        count = mutex.synchronize do
          entries = requests[intent_hash]
          return false unless entries

          entries.reject! { |t| t < window }
          entries.size
        end

        count > rapid_fire_threshold
      end

      def max_stale_seconds
        setting(:max_stale_seconds) || DEFAULT_MAX_STALE_SECONDS
      end

      def rapid_fire_threshold
        setting(:rapid_fire_threshold) || DEFAULT_RAPID_FIRE_THRESHOLD
      end

      def rapid_fire_window_seconds
        setting(:rapid_fire_window_seconds) || DEFAULT_RAPID_FIRE_WINDOW_SECS
      end

      def anomaly_miss_threshold
        DEFAULT_ANOMALY_MISS_THRESHOLD
      end

      def setting(key)
        Legion::Settings.dig(:mcp, :tier0, :guards, key)
      rescue StandardError => e
        handle_exception(e, level: :warn, operation: 'legion.mcp.context_guard.setting')
        log.warn("ContextGuard#setting failed for key #{key}: #{e.message}")
        nil
      end

      def staleness_failure(pattern)
        age = pattern[:last_hit_at] ? (Time.now - pattern[:last_hit_at]).round(0) : 0
        { passed: false, guard: :staleness, reason: "pattern stale (#{age}s since last hit)" }
      end

      def anomaly_failure(pattern)
        { passed: false, guard: :anomaly, reason: "#{pattern[:miss_count]} consecutive misses" }
      end

      def rapid_fire_failure(_pattern)
        { passed: false, guard: :rapid_fire,
          reason: "exceeded #{rapid_fire_threshold} requests in #{rapid_fire_window_seconds}s" }
      end

      def requests
        @requests ||= {}
      end

      def mutex
        @mutex ||= Mutex.new
      end
    end
  end
end
