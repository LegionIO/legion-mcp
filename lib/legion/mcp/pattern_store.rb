# frozen_string_literal: true

require 'json'
require_relative 'utils'

module Legion
  module MCP
    module PatternStore # rubocop:disable Metrics/ModuleLength
      CONFIDENCE_SUCCESS_DELTA = 0.02
      CONFIDENCE_FAILURE_DELTA = -0.05
      SEEDED_CONFIDENCE        = 0.5
      DECAY_ARCHIVE_THRESHOLD  = 0.1

      extend Legion::Logging::Helper

      module_function

      def mcp_log(level, event, **fields)
        log.public_send(level, "[mcp] #{event} #{Utils.format_fields(fields)}")
      end

      def store(pattern = nil, request_id: nil, **attrs)
        pattern = (pattern || {}).merge(attrs)
        hash = pattern[:intent_hash]
        mutex.synchronize { patterns_l0[hash] = pattern.dup }
        persist_l1(hash, pattern)
        persist_l2(hash, pattern)
        mcp_log :info, 'pattern.store',
                request_id: request_id, intent_hash: hash&.[](0, 12),
                intent: pattern[:intent_text],
                confidence: pattern[:confidence]&.round(3),
                tool_chain: Array(pattern[:tool_chain])
      end

      def lookup(intent_hash, request_id: nil) # rubocop:disable Metrics/AbcSize, Metrics/MethodLength
        result = mutex.synchronize { patterns_l0[intent_hash]&.dup }
        if result
          mcp_log :info, 'pattern.lookup',
                  request_id: request_id, source: :l0,
                  intent_hash: intent_hash&.[](0, 12),
                  confidence: result[:confidence]&.round(3),
                  tool_chain: Array(result[:tool_chain])
          return result
        end

        result = lookup_l1(intent_hash)
        if result
          mutex.synchronize { patterns_l0[intent_hash] = result }
          mcp_log :info, 'pattern.lookup',
                  request_id: request_id, source: :l1,
                  intent_hash: intent_hash&.[](0, 12),
                  confidence: result[:confidence]&.round(3),
                  tool_chain: Array(result[:tool_chain])
          return result.dup
        end

        result = lookup_l2(intent_hash)
        if result
          mutex.synchronize { patterns_l0[intent_hash] = result }
          persist_l1(intent_hash, result)
          mcp_log :info, 'pattern.lookup',
                  request_id: request_id, source: :l2,
                  intent_hash: intent_hash&.[](0, 12),
                  confidence: result[:confidence]&.round(3),
                  tool_chain: Array(result[:tool_chain])
          return result.dup
        end

        mcp_log :info, 'pattern.lookup',
                request_id: request_id, source: :miss, intent_hash: intent_hash&.[](0, 12)

        nil
      end

      def lookup_semantic(intent_vector, threshold: 0.85, request_id: nil)
        return nil unless intent_vector && !patterns_l0.empty?

        best_hash = nil
        best_score = 0.0

        mutex.synchronize do
          patterns_l0.each do |hash, pattern|
            next unless pattern[:intent_vector]

            score = cosine_similarity(intent_vector, pattern[:intent_vector])
            if score > best_score && score >= threshold
              best_score = score
              best_hash = hash
            end
          end
        end

        mcp_log :info, 'pattern.semantic_lookup',
                request_id: request_id, matched: !best_hash.nil?,
                best_score: best_score.round(4), threshold: threshold,
                intent_hash: best_hash&.[](0, 12)
        best_hash ? lookup(best_hash, request_id: request_id) : nil
      end

      def record_hit(intent_hash, request_id: nil)
        mutex.synchronize do
          pattern = patterns_l0[intent_hash]
          return unless pattern

          pattern[:hit_count] = (pattern[:hit_count] || 0) + 1
          pattern[:miss_count] = 0
          pattern[:last_hit_at] = Time.now
          pattern[:confidence] = (pattern[:confidence] + CONFIDENCE_SUCCESS_DELTA).clamp(0.0, 1.0)
        end
        sync_to_persistence(intent_hash)
        pattern = mutex.synchronize { patterns_l0[intent_hash]&.dup }
        mcp_log :info, 'pattern.hit',
                request_id: request_id, intent_hash: intent_hash&.[](0, 12),
                confidence: pattern&.dig(:confidence)&.round(3),
                hit_count: pattern&.dig(:hit_count)
      end

      def record_miss(intent_hash, request_id: nil)
        mutex.synchronize do
          pattern = patterns_l0[intent_hash]
          return unless pattern

          pattern[:miss_count] = (pattern[:miss_count] || 0) + 1
          pattern[:confidence] = (pattern[:confidence] + CONFIDENCE_FAILURE_DELTA).clamp(0.0, 1.0)
        end
        sync_to_persistence(intent_hash)
        pattern = mutex.synchronize { patterns_l0[intent_hash]&.dup }
        mcp_log :info, 'pattern.miss',
                request_id: request_id, intent_hash: intent_hash&.[](0, 12),
                confidence: pattern&.dig(:confidence)&.round(3),
                miss_count: pattern&.dig(:miss_count)
      end

      def promote_candidate(intent_hash:, tool_chain:, intent_text:, intent_vector: nil, candidate_key: nil, request_id: nil) # rubocop:disable Metrics/ParameterLists
        pattern = {
          intent_hash:          intent_hash,
          intent_text:          intent_text,
          intent_vector:        intent_vector,
          tool_chain:           tool_chain,
          response_template:    nil,
          confidence:           SEEDED_CONFIDENCE,
          hit_count:            0,
          miss_count:           0,
          last_hit_at:          nil,
          created_at:           Time.now,
          context_requirements: nil
        }
        store(pattern, request_id: request_id)
        buf_key = candidate_key || intent_hash
        candidates_mutex.synchronize { candidates_buffer.delete(buf_key) }
        mcp_log :info, 'pattern.promoted',
                request_id: request_id, intent_hash: intent_hash&.[](0, 12),
                intent: intent_text, tool_chain: Array(tool_chain)
        pattern
      end

      def record_candidate(intent_hash:, tool_chain:, intent_text:, candidate_key: nil, threshold: 3, request_id: nil) # rubocop:disable Metrics/ParameterLists
        buf_key = candidate_key || intent_hash
        candidates_mutex.synchronize do
          entry = candidates_buffer[buf_key] ||= { intent_text: intent_text, tool_chain: tool_chain,
                                                   count: 0 }
          entry[:count] += 1

          if entry[:count] == 1
            mcp_log :info, 'pattern.candidate.recorded',
                    request_id: request_id, intent_hash: intent_hash&.[](0, 12),
                    intent: intent_text, tool_chain: Array(tool_chain),
                    count: entry[:count], threshold: threshold
          end

          if entry[:count] >= threshold && !pattern_exists?(intent_hash)
            candidates_buffer.delete(buf_key)
            mcp_log :info, 'pattern.candidate.threshold_met',
                    request_id: request_id, intent_hash: intent_hash&.[](0, 12),
                    intent: intent_text, tool_chain: Array(tool_chain),
                    count: entry[:count], threshold: threshold
            return { promote: true, intent_hash: intent_hash, tool_chain: tool_chain,
                     intent_text: intent_text }
          end
        end
        nil
      end

      def candidates
        candidates_mutex.synchronize { candidates_buffer.dup }
      end

      def patterns
        mutex.synchronize { patterns_l0.dup }
      end

      def size
        mutex.synchronize { patterns_l0.size }
      end

      def empty?
        size.zero?
      end

      def stats
        total_hits = 0
        total_conf = 0.0
        count = 0

        mutex.synchronize do
          patterns_l0.each_value do |p|
            total_hits += p[:hit_count] || 0
            total_conf += p[:confidence] || 0.0
            count += 1
          end
        end

        {
          size:           count,
          hit_rate:       count.positive? ? (total_hits.to_f / [count, 1].max).round(2) : 0.0,
          avg_confidence: count.positive? ? (total_conf / count).round(4) : 0.0
        }
      end

      def learn_response_template(intent_hash, result_data, threshold: 3, request_id: nil)
        return unless result_data.is_a?(Hash)

        template_mutex.synchronize do
          buffer = template_observations[intent_hash] ||= []
          buffer << result_data.keys.sort
          buffer.shift if buffer.size > 10

          return unless buffer.size >= threshold

          if buffer.last(threshold).uniq.size == 1
            keys = buffer.last.sort
            template = keys.map { |k| "#{k}: {{#{k}}}" }.join(', ')
            mutex.synchronize do
              pattern = patterns_l0[intent_hash]
              pattern[:response_template] = template if pattern
            end
            sync_to_persistence(intent_hash)
            mcp_log :info, 'pattern.template.learned',
                    request_id: request_id, intent_hash: intent_hash&.[](0, 12),
                    template: Utils.summarize_text(template)
          end
        end
      end

      def decay_all(factor: 0.998)
        log.debug("[mcp][pattern_store] action=decay_all factor=#{factor} patterns=#{size}")
        archived = []
        mutex.synchronize do
          patterns_l0.each do |hash, pattern|
            pattern[:confidence] = (pattern[:confidence] * factor).clamp(0.0, 1.0)
            archived << hash if pattern[:confidence] < DECAY_ARCHIVE_THRESHOLD
          end
          archived.each { |hash| patterns_l0.delete(hash) }
        end

        archived.each do |hash|
          archive_l2(hash)
          evict_l1(hash)
        end
        sync_all_to_persistence
        log.debug("[mcp][pattern_store] action=decay_all.complete archived=#{archived.size} remaining=#{size}")
      end

      def hydrate_from_l2
        return unless local_db_available?

        table = ensure_local_table
        loaded = 0
        table.each do |row|
          pattern = deserialize_pattern(row)
          mutex.synchronize { patterns_l0[pattern[:intent_hash]] = pattern }
          persist_l1(pattern[:intent_hash], pattern)
          loaded += 1
        end
        mcp_log :info, 'pattern.hydrate.complete', source: :l2, loaded: loaded
      rescue StandardError => e
        handle_exception(e, level: :warn, operation: 'legion.mcp.pattern_store.hydrate_from_l2')
        nil
      end

      def reset!
        mutex.synchronize { patterns_l0.clear }
        candidates_mutex.synchronize { candidates_buffer.clear }
        template_mutex.synchronize { template_observations.clear }
      end

      # --- Private helpers ---

      def pattern_exists?(intent_hash)
        mutex.synchronize { patterns_l0.key?(intent_hash) }
      end

      def cosine_similarity(vec_a, vec_b)
        return 0.0 if vec_a.nil? || vec_b.nil? || vec_a.empty? || vec_b.empty?

        dot = vec_a.zip(vec_b).sum { |a, b| a * b }
        mag_a = Math.sqrt(vec_a.sum { |x| x**2 })
        mag_b = Math.sqrt(vec_b.sum { |x| x**2 })
        return 0.0 if mag_a.zero? || mag_b.zero?

        dot / (mag_a * mag_b)
      end

      # --- L1: Cache (optional) ---

      def persist_l1(intent_hash, pattern)
        return unless defined?(Legion::Cache) && Legion::Cache.respond_to?(:connected?) && Legion::Cache.connected?

        Legion::Cache.set("tbi:pattern:#{intent_hash}", Legion::JSON.dump(pattern), 3600)
      rescue StandardError => e
        handle_exception(e, level: :warn, operation: 'legion.mcp.pattern_store.persist_l1')
        nil
      end

      def evict_l1(intent_hash)
        return unless defined?(Legion::Cache) && Legion::Cache.respond_to?(:connected?) && Legion::Cache.connected?

        Legion::Cache.delete("tbi:pattern:#{intent_hash}")
      rescue StandardError => e
        handle_exception(e, level: :warn, operation: 'legion.mcp.pattern_store.evict_l1')
        nil
      end

      def lookup_l1(intent_hash)
        return nil unless defined?(Legion::Cache) && Legion::Cache.respond_to?(:connected?) && Legion::Cache.connected?

        raw = Legion::Cache.get("tbi:pattern:#{intent_hash}")
        raw ? Legion::JSON.load(raw) : nil
      rescue StandardError => e
        handle_exception(e, level: :warn, operation: 'legion.mcp.pattern_store.lookup_l1')
        nil
      end

      # --- L2: Data::Local SQLite (optional) ---

      def persist_l2(intent_hash, pattern)
        return unless local_db_available?

        table = ensure_local_table
        data = serialize_pattern(pattern)
        if table.where(intent_hash: intent_hash).first
          table.where(intent_hash: intent_hash).update(data)
        else
          table.insert(data)
        end
      rescue StandardError => e
        handle_exception(e, level: :warn, operation: 'legion.mcp.pattern_store.persist_l2')
        nil
      end

      def lookup_l2(intent_hash)
        return nil unless local_db_available?

        table = ensure_local_table
        row = table.where(intent_hash: intent_hash).first
        row ? deserialize_pattern(row) : nil
      rescue StandardError => e
        handle_exception(e, level: :warn, operation: 'legion.mcp.pattern_store.lookup_l2')
        nil
      end

      def sync_to_persistence(intent_hash)
        pattern = mutex.synchronize { patterns_l0[intent_hash]&.dup }
        return unless pattern

        persist_l1(intent_hash, pattern)
        persist_l2(intent_hash, pattern)
      end

      def archive_l2(intent_hash)
        return unless local_db_available?

        table = ensure_local_table
        table.where(intent_hash: intent_hash).delete
      rescue StandardError => e
        handle_exception(e, level: :warn, operation: 'legion.mcp.pattern_store.archive_l2')
        nil
      end

      def sync_all_to_persistence
        mutex.synchronize { patterns_l0.keys.dup }.each { |h| sync_to_persistence(h) }
      end

      def local_db_available?
        defined?(Legion::Data::Local) &&
          Legion::Data::Local.respond_to?(:connected?) &&
          Legion::Data::Local.connected?
      end

      def ensure_local_table
        db = Legion::Data::Local.connection
        unless db.table_exists?(:tbi_patterns)
          db.create_table(:tbi_patterns) do
            primary_key :id
            String :intent_hash, null: false, unique: true
            String :intent_text, text: true
            String :intent_vector, text: true
            String :tool_chain, text: true, null: false
            String :response_template, text: true
            Float :confidence, default: 0.5
            Integer :hit_count, default: 0
            Integer :miss_count, default: 0
            DateTime :last_hit_at
            DateTime :created_at
            String :context_requirements, text: true
          end
        end
        db[:tbi_patterns]
      end

      def serialize_pattern(pattern)
        {
          intent_hash:          pattern[:intent_hash],
          intent_text:          pattern[:intent_text],
          intent_vector:        pattern[:intent_vector] ? ::JSON.dump(pattern[:intent_vector]) : nil,
          tool_chain:           ::JSON.dump(pattern[:tool_chain]),
          response_template:    pattern[:response_template],
          confidence:           pattern[:confidence],
          hit_count:            pattern[:hit_count],
          miss_count:           pattern[:miss_count],
          last_hit_at:          pattern[:last_hit_at],
          created_at:           pattern[:created_at],
          context_requirements: pattern[:context_requirements]&.then { |c| ::JSON.dump(c) }
        }
      end

      def deserialize_pattern(row)
        {
          intent_hash:          row[:intent_hash],
          intent_text:          row[:intent_text],
          intent_vector:        row[:intent_vector] ? ::JSON.parse(row[:intent_vector]) : nil,
          tool_chain:           ::JSON.parse(row[:tool_chain]),
          response_template:    row[:response_template],
          confidence:           row[:confidence],
          hit_count:            row[:hit_count],
          miss_count:           row[:miss_count],
          last_hit_at:          row[:last_hit_at],
          created_at:           row[:created_at],
          context_requirements: row[:context_requirements] ? ::JSON.parse(row[:context_requirements]) : nil
        }
      end

      def patterns_l0
        @patterns_l0 ||= {}
      end

      def mutex
        @mutex ||= Mutex.new
      end

      def candidates_buffer
        @candidates_buffer ||= {}
      end

      def candidates_mutex
        @candidates_mutex ||= Mutex.new
      end

      def template_observations
        @template_observations ||= {}
      end

      def template_mutex
        @template_mutex ||= Mutex.new
      end
    end
  end
end
