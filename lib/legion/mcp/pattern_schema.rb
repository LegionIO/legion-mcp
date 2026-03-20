# frozen_string_literal: true

require 'digest'

module Legion
  module MCP
    module PatternSchema
      SCHEMA_VERSION = '1.0'
      REQUIRED_FIELDS = %i[schema_version pattern_id intent capability_chain confidence metadata].freeze

      TRUST_LEVELS = {
        local:     0.5,
        org:       0.4,
        community: 0.3
      }.freeze

      module_function

      def export(pattern)
        {
          schema_version:    SCHEMA_VERSION,
          pattern_id:        pattern[:intent_hash],
          intent:            {
            description: pattern[:intent_text],
            keywords:    extract_keywords(pattern[:intent_text])
          },
          capability_chain:  Array(pattern[:tool_chain]).map { |t| { tool: t, params_template: {} } },
          response_template: pattern[:response_template] ? { engine: 'mustache', template: pattern[:response_template] } : nil,
          confidence:        {
            suggested_initial: [pattern[:confidence], 0.5].min,
            source_hits:       pattern[:hit_count] || 0,
            source_misses:     pattern[:miss_count] || 0
          },
          metadata:          {
            source:      'local',
            sensitivity: 'public',
            created_at:  pattern[:created_at]&.iso8601
          }
        }
      end

      def import(external, trust_level: :community)
        confidence = external.dig(:confidence, :suggested_initial) || TRUST_LEVELS.fetch(trust_level, 0.3)
        confidence = [confidence, TRUST_LEVELS.fetch(trust_level, 0.3)].min

        intent_text = external.dig(:intent, :description) || ''
        intent_hash = external[:pattern_id] || Digest::SHA256.hexdigest(intent_text.downcase.strip)
        tool_chain = Array(external[:capability_chain]).map { |c| c[:tool] || c.to_s }

        template = external.dig(:response_template, :template)

        {
          intent_hash:          intent_hash,
          intent_text:          intent_text,
          intent_vector:        nil,
          tool_chain:           tool_chain,
          response_template:    template,
          confidence:           confidence,
          hit_count:            0,
          miss_count:           0,
          last_hit_at:          nil,
          created_at:           Time.now,
          context_requirements: nil
        }
      end

      def validate_schema(data)
        return false unless data.is_a?(Hash)

        REQUIRED_FIELDS.all? { |f| data.key?(f) }
      end

      def extract_keywords(text)
        return [] unless text

        text.downcase.split(/\s+/).uniq.reject { |w| w.length < 3 }
      end
    end
  end
end
