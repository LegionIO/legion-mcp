# frozen_string_literal: true

require 'digest'

module Legion
  module MCP
    module SelfGenerate
      MAX_GAPS_PER_CYCLE = 5
      COOLDOWN_SECONDS   = 300

      module_function

      def run_cycle
        return { success: false, reason: :cooldown } if in_cooldown?

        gaps = GapDetector.detect_gaps
        return { success: true, gaps_found: 0, generated: 0 } if gaps.empty?

        top_gaps = gaps.sort_by { |g| -g[:priority] }.first(MAX_GAPS_PER_CYCLE)

        results = top_gaps.map do |gap|
          result = FunctionGenerator.generate_from_gap(gap)
          { gap: gap[:id], type: gap[:type], result: result }
        end

        record_cycle(results)

        generated = results.count { |r| r[:result][:success] }
        failed    = results.count { |r| !r[:result][:success] }

        {
          success:    true,
          gaps_found: gaps.size,
          processed:  top_gaps.size,
          generated:  generated,
          failed:     failed,
          results:    results
        }
      end

      def status
        {
          last_cycle_at:      last_cycle_at,
          total_cycles:       cycle_count,
          total_generated:    total_generated,
          cooldown_remaining: cooldown_remaining,
          pending_gaps:       GapDetector.detect_gaps.size
        }
      rescue StandardError => e
        { error: e.message }
      end

      def reset!
        mutex.synchronize do
          @last_cycle_at   = nil
          @cycle_count     = 0
          @total_generated = 0
          @cycle_history   = []
        end
      end

      def cycle_history(limit = 10)
        mutex.synchronize { (@cycle_history || []).last(limit) }
      end

      def in_cooldown?
        return false unless last_cycle_at

        Time.now - last_cycle_at < COOLDOWN_SECONDS
      end

      def cooldown_remaining
        return 0 unless last_cycle_at

        remaining = COOLDOWN_SECONDS - (Time.now - last_cycle_at)
        [remaining, 0].max.round(1)
      end

      def record_cycle(results)
        mutex.synchronize do
          @last_cycle_at   = Time.now
          @cycle_count     = (@cycle_count || 0) + 1
          @total_generated = (@total_generated || 0) + results.count { |r| r[:result][:success] }
          @cycle_history ||= []
          @cycle_history << {
            at:            Time.now,
            results_count: results.size,
            generated:     results.count { |r| r[:result][:success] }
          }
          @cycle_history.shift if @cycle_history.size > 50
        end
      end

      def last_cycle_at
        mutex.synchronize { @last_cycle_at }
      end

      def cycle_count
        mutex.synchronize { @cycle_count || 0 }
      end

      def total_generated
        mutex.synchronize { @total_generated || 0 }
      end

      def mutex
        @mutex ||= Mutex.new
      end
    end
  end
end
