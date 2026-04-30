# frozen_string_literal: true

module Legion
  module MCP
    module StateTracker
      MAX_SNAPSHOTS = 50

      extend Legion::Logging::Helper

      module_function

      def snapshot
        log.debug('[mcp][state_tracker] action=snapshot')
        state = collect_state
        timestamp = Time.now.floor

        snapshots_mutex.synchronize do
          snapshots << { state: state, timestamp: timestamp }
          snapshots.shift if snapshots.size > MAX_SNAPSHOTS
        end

        { state: state, timestamp: timestamp.iso8601 }
      end

      def diff(since:)
        log.debug("[mcp][state_tracker] action=diff since=#{since}")
        since_time = parse_time(since)
        return { error: 'invalid timestamp' } unless since_time

        baseline = find_baseline(since_time)
        current = collect_state

        if baseline.nil?
          return { full_state: current, reason: 'no baseline found for given timestamp',
                   timestamp: Time.now.iso8601 }
        end

        changes = compute_diff(baseline[:state], current)
        { changes: changes, since: since_time.iso8601, timestamp: Time.now.iso8601 }
      end

      def collect_state
        {
          tool_count:     Server.tool_registry.size,
          observer_stats: collect_observer_stats,
          pattern_count:  collect_pattern_count,
          extensions:     collect_extension_count
        }
      end

      def collect_observer_stats
        return {} unless defined?(Observer)

        stats = Observer.stats
        { total_calls: stats[:total_calls], tool_count: stats[:tool_count], failure_rate: stats[:failure_rate] }
      rescue StandardError => e
        handle_exception(e, level: :debug, operation: 'legion.mcp.state_tracker.collect_observer_stats')
        {}
      end

      def collect_pattern_count
        return 0 unless defined?(Patterns::Store)

        Patterns::Store.respond_to?(:size) ? Patterns::Store.size : 0
      rescue StandardError => e
        handle_exception(e, level: :debug, operation: 'legion.mcp.state_tracker.collect_pattern_count')
        0
      end

      def collect_extension_count
        return 0 unless defined?(Legion::Extensions)

        extensions = if Legion::Extensions.respond_to?(:extensions)
                       Legion::Extensions.extensions
                     else
                       Legion::Extensions.instance_variable_get(:@extensions)
                     end
        extensions&.size || 0
      rescue StandardError => e
        handle_exception(e, level: :debug, operation: 'legion.mcp.state_tracker.collect_extension_count')
        0
      end

      def compute_diff(baseline, current)
        changes = {}
        all_keys = (baseline.keys | current.keys).uniq

        all_keys.each do |key|
          old_val = baseline[key]
          new_val = current[key]

          next if old_val == new_val

          if old_val.is_a?(Hash) && new_val.is_a?(Hash)
            nested = compute_diff(old_val, new_val)
            changes[key] = nested unless nested.empty?
          else
            changes[key] = { before: old_val, after: new_val }
          end
        end

        changes
      end

      def find_baseline(since_time)
        snapshots_mutex.synchronize do
          snapshots.reverse.find { |s| s[:timestamp] <= since_time }
        end
      end

      def parse_time(value)
        case value
        when Time
          value
        when String
          Time.parse(value)
        when Numeric
          Time.at(value)
        end
      rescue ArgumentError => e
        handle_exception(e, level: :debug, operation: 'legion.mcp.state_tracker.parse_time')
        nil
      end

      def snapshots
        @snapshots ||= []
      end

      def snapshots_mutex
        @snapshots_mutex ||= Mutex.new
      end

      def reset!
        snapshots_mutex.synchronize { snapshots.clear }
      end
    end
  end
end
