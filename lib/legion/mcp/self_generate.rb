# frozen_string_literal: true

require 'digest'
require 'time'

module Legion
  module MCP
    module SelfGenerate
      MAX_GAPS_PER_CYCLE = 5
      COOLDOWN_SECONDS   = 300

      extend Legion::Logging::Helper

      module_function

      def enabled?
        return false unless defined?(Legion::Settings)

        Legion::Settings.dig(:codegen, :self_generate, :enabled) == true
      end

      def run_cycle
        log.info('Starting legion.mcp.self_generate.run_cycle')
        return { success: false, reason: :disabled } unless enabled?
        return { success: false, reason: :cooldown } if in_cooldown?

        gaps = GapDetector.detect_gaps
        return { success: true, gaps_found: 0, published: 0 } if gaps.empty?

        top_gaps = gaps.sort_by { |g| -g[:priority] }.first(max_gaps_per_cycle)

        published_count = 0
        top_gaps.each do |gap|
          published_count += 1 if publish_gap(gap)
        end

        if published_count.zero?
          reason = defined?(Legion::Transport::Messages::Dynamic) ? :publish_failed : :transport_unavailable
          return {
            success:    false,
            reason:     reason,
            gaps_found: gaps.size,
            processed:  top_gaps.size,
            published:  0
          }
        end

        record_cycle(published_count)

        {
          success:    true,
          gaps_found: gaps.size,
          processed:  top_gaps.size,
          published:  published_count
        }
      end

      def publish_gap(gap)
        return false unless defined?(Legion::Transport::Messages::Dynamic)

        Legion::Transport::Messages::Dynamic.new(
          function: 'codegen.gap.detected',
          data:     {
            gap_id:           gap[:id],
            gap_type:         gap[:type],
            intent:           gap[:intent] || gap[:intent_text],
            occurrence_count: gap[:occurrences] || gap[:observation_count] || gap[:failure_count] || 1,
            priority:         gap[:priority],
            metadata:         gap[:metadata] || {},
            detected_at:      Time.now.iso8601
          }
        ).publish
        true
      rescue StandardError => e
        handle_exception(e, level: :warn, operation: 'legion.mcp.self_generate.publish_gap')
        log.warn("SelfGenerate#publish_gap failed: #{e.message}")
        false
      end

      def status
        log.info('Starting legion.mcp.self_generate.status')
        {
          last_cycle_at:      last_cycle_at,
          total_cycles:       cycle_count,
          total_published:    total_published,
          cooldown_remaining: cooldown_remaining,
          pending_gaps:       GapDetector.detect_gaps.size,
          enabled:            enabled?
        }
      rescue StandardError => e
        handle_exception(e, level: :error, operation: 'legion.mcp.self_generate.status')
        { error: e.message }
      end

      def reset!
        mutex.synchronize do
          @last_cycle_at   = nil
          @cycle_count     = 0
          @total_published = 0
          @cycle_history   = []
        end
      end

      def cycle_history(limit = 10)
        mutex.synchronize { (@cycle_history || []).last(limit) }
      end

      def in_cooldown?
        return false unless last_cycle_at

        Time.now - last_cycle_at < cooldown_seconds
      end

      def cooldown_remaining
        return 0 unless last_cycle_at

        remaining = cooldown_seconds - (Time.now - last_cycle_at)
        [remaining, 0].max.round(1)
      end

      def total_published
        mutex.synchronize { @total_published || 0 }
      end

      # private helpers

      def max_gaps_per_cycle
        val = Legion::Settings.dig(:codegen, :self_generate, :max_gaps_per_cycle) if defined?(Legion::Settings)
        val || MAX_GAPS_PER_CYCLE
      end

      def cooldown_seconds
        val = Legion::Settings.dig(:codegen, :self_generate, :cooldown_seconds) if defined?(Legion::Settings)
        val || COOLDOWN_SECONDS
      end

      def record_cycle(published_count)
        mutex.synchronize do
          @last_cycle_at   = Time.now
          @cycle_count     = (@cycle_count || 0) + 1
          @total_published = (@total_published || 0) + published_count
          @cycle_history ||= []
          @cycle_history << { at: Time.now, published: published_count }
          @cycle_history.shift if @cycle_history.size > 50
        end
      end

      def last_cycle_at
        mutex.synchronize { @last_cycle_at }
      end

      def cycle_count
        mutex.synchronize { @cycle_count || 0 }
      end

      def mutex
        @mutex ||= Mutex.new
      end
    end
  end
end
