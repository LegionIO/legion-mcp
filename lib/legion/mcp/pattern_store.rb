# frozen_string_literal: true

require 'json'

module Legion
  module MCP
    module PatternStore
      CONFIDENCE_SUCCESS_DELTA = 0.02
      CONFIDENCE_FAILURE_DELTA = -0.05
      SEEDED_CONFIDENCE        = 0.5

      module_function

      def store(pattern)
        hash = pattern[:intent_hash]
        mutex.synchronize { patterns_l0[hash] = pattern.dup }
        persist_l1(hash, pattern)
        persist_l2(hash, pattern)
      end

      def lookup(intent_hash)
        result = mutex.synchronize { patterns_l0[intent_hash]&.dup }
        return result if result

        result = lookup_l1(intent_hash)
        if result
          mutex.synchronize { patterns_l0[intent_hash] = result }
          return result.dup
        end

        result = lookup_l2(intent_hash)
        if result
          mutex.synchronize { patterns_l0[intent_hash] = result }
          persist_l1(intent_hash, result)
          return result.dup
        end

        nil
      end

      def lookup_semantic(intent_vector, threshold: 0.85)
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

        best_hash ? lookup(best_hash) : nil
      end

      def record_hit(intent_hash)
        mutex.synchronize do
          pattern = patterns_l0[intent_hash]
          return unless pattern

          pattern[:hit_count] = (pattern[:hit_count] || 0) + 1
          pattern[:miss_count] = 0
          pattern[:last_hit_at] = Time.now
          pattern[:confidence] = (pattern[:confidence] + CONFIDENCE_SUCCESS_DELTA).clamp(0.0, 1.0)
        end
        sync_to_persistence(intent_hash)
      end

      def record_miss(intent_hash)
        mutex.synchronize do
          pattern = patterns_l0[intent_hash]
          return unless pattern

          pattern[:miss_count] = (pattern[:miss_count] || 0) + 1
          pattern[:confidence] = (pattern[:confidence] + CONFIDENCE_FAILURE_DELTA).clamp(0.0, 1.0)
        end
        sync_to_persistence(intent_hash)
      end

      def promote_candidate(intent_hash:, tool_chain:, intent_text:, intent_vector: nil)
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
        store(pattern)
        candidates_mutex.synchronize { candidates_buffer.delete(intent_hash) }
        pattern
      end

      def record_candidate(intent_hash:, tool_chain:, intent_text:, threshold: 3)
        candidates_mutex.synchronize do
          entry = candidates_buffer[intent_hash] ||= { intent_text: intent_text, tool_chain: tool_chain,
                                                       count: 0 }
          entry[:count] += 1

          if entry[:count] >= threshold && !pattern_exists?(intent_hash)
            candidates_buffer.delete(intent_hash)
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

      def reset!
        mutex.synchronize { patterns_l0.clear }
        candidates_mutex.synchronize { candidates_buffer.clear }
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
      rescue StandardError
        nil
      end

      def lookup_l1(intent_hash)
        return nil unless defined?(Legion::Cache) && Legion::Cache.respond_to?(:connected?) && Legion::Cache.connected?

        raw = Legion::Cache.get("tbi:pattern:#{intent_hash}")
        raw ? Legion::JSON.load(raw) : nil
      rescue StandardError
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
      rescue StandardError
        nil
      end

      def lookup_l2(intent_hash)
        return nil unless local_db_available?

        table = ensure_local_table
        row = table.where(intent_hash: intent_hash).first
        row ? deserialize_pattern(row) : nil
      rescue StandardError
        nil
      end

      def sync_to_persistence(intent_hash)
        pattern = mutex.synchronize { patterns_l0[intent_hash]&.dup }
        return unless pattern

        persist_l1(intent_hash, pattern)
        persist_l2(intent_hash, pattern)
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
    end
  end
end
