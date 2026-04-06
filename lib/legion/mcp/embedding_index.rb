# frozen_string_literal: true

module Legion
  module MCP
    module EmbeddingIndex
      extend Legion::Logging::Helper

      module_function

      def build_from_tool_data(tool_data, embedder: default_embedder)
        @embedder = embedder
        mutex.synchronize do
          composites = tool_data.to_h do |tool|
            [tool[:name], build_composite(tool[:name], tool[:description], tool[:params])]
          end

          cached_vectors = bulk_cache_lookup(composites.values)

          uncached_names = composites.keys.reject { |name| cached_vectors.key?(composites[name]) }
          newly_embedded = {}
          uncached_names.each do |name|
            composite = composites[name]
            vector = safe_embed(composite, embedder)
            newly_embedded[composite] = vector if vector
          end

          bulk_cache_store(newly_embedded) unless newly_embedded.empty?

          tool_data.each do |tool|
            composite = composites[tool[:name]]
            vector = cached_vectors[composite] || newly_embedded[composite]
            next unless vector

            index[tool[:name]] = {
              name:           tool[:name],
              composite_text: composite,
              vector:         vector,
              built_at:       Time.now
            }
          end
        end
      end

      def semantic_match(intent, embedder: @embedder || default_embedder, limit: 5)
        return [] if index.empty?

        intent_vec = safe_embed(intent, embedder)
        return [] unless intent_vec

        scores = mutex.synchronize do
          index.values.filter_map do |entry|
            next unless entry[:vector]

            score = cosine_similarity(intent_vec, entry[:vector])
            { name: entry[:name], score: score }
          end
        end

        scores.sort_by { |s| -s[:score] }.first(limit)
      end

      def cosine_similarity(vec_a, vec_b)
        dot = vec_a.zip(vec_b).sum { |a, b| a * b }
        mag_a = Math.sqrt(vec_a.sum { |x| x**2 })
        mag_b = Math.sqrt(vec_b.sum { |x| x**2 })
        return 0.0 if mag_a.zero? || mag_b.zero?

        dot / (mag_a * mag_b)
      end

      def entry(tool_name)
        mutex.synchronize { index[tool_name] }
      end

      def size
        mutex.synchronize { index.size }
      end

      def populated?
        mutex.synchronize { !index.empty? }
      end

      def coverage
        mutex.synchronize do
          return 0.0 if index.empty?

          with_vectors = index.values.count { |e| e[:vector] }
          with_vectors.to_f / index.size
        end
      end

      def reset!
        @embedder = nil
        mutex.synchronize { index.clear }
      end

      def index
        @index ||= {}
      end

      def mutex
        @mutex ||= Mutex.new
      end

      def bulk_cache_lookup(composite_texts)
        return {} unless defined?(Legion::Tools::EmbeddingCache) &&
                         Legion::Tools::EmbeddingCache.respond_to?(:bulk_lookup)

        Legion::Tools::EmbeddingCache.bulk_lookup(composite_texts)
      rescue StandardError => e
        handle_exception(e, level: :debug, operation: 'legion.mcp.embedding_index.bulk_cache_lookup')
        {}
      end

      def bulk_cache_store(composite_to_vector)
        return unless defined?(Legion::Tools::EmbeddingCache) &&
                      Legion::Tools::EmbeddingCache.respond_to?(:bulk_store)

        Legion::Tools::EmbeddingCache.bulk_store(composite_to_vector)
      rescue StandardError => e
        handle_exception(e, level: :debug, operation: 'legion.mcp.embedding_index.bulk_cache_store')
        nil
      end

      def build_composite(name, description, params)
        parts = [name, '--', description]
        parts << "Params: #{params.join(', ')}" unless params.empty?
        parts.join(' ')
      end

      def safe_embed(text, embedder)
        return nil unless embedder

        result = embedder.call(text)
        return nil unless result.is_a?(Array) && !result.empty?

        result
      rescue StandardError => e
        handle_exception(e, level: :debug, operation: 'legion.mcp.embedding_index.safe_embed')
        log.debug("EmbeddingIndex#safe_embed failed: #{e.message}")
        nil
      end

      def default_embedder
        return nil unless defined?(Legion::LLM) && Legion::LLM.respond_to?(:started?) && Legion::LLM.started?

        ->(text) { Legion::LLM.embed(text)[:vector] }
      rescue StandardError => e
        handle_exception(e, level: :debug, operation: 'legion.mcp.embedding_index.default_embedder')
        log.debug("EmbeddingIndex#default_embedder failed: #{e.message}")
        nil
      end
    end
  end
end
