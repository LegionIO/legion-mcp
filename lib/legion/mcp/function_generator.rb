# frozen_string_literal: true

require 'digest'

module Legion
  module MCP
    module FunctionGenerator
      MAX_GENERATION_ATTEMPTS = 3
      GENERATION_TIMEOUT      = 60

      module_function

      def generate_from_gap(gap)
        case gap[:type]
        when :unmatched_intent
          generate_tool_for_intent(intent: gap[:intent])
        when :high_failure_tool
          generate_fix_for_tool(tool_name: gap[:tool_name], last_error: gap[:last_error])
        when :stale_candidate
          generate_tool_for_candidate(intent_text: gap[:intent_text], tool_chain: gap[:tool_chain])
        else
          { success: false, reason: :unknown_gap_type }
        end
      rescue StandardError => e
        { success: false, reason: :generation_failed, error: e.message }
      end

      def generate_tool_for_intent(intent:)
        return { success: false, reason: :llm_not_available } unless llm_available?

        spec = generate_tool_spec(intent: intent)
        return spec unless spec[:success]

        validate_spec(spec[:tool_spec])
      end

      def generate_fix_for_tool(tool_name:, last_error:)
        return { success: false, reason: :llm_not_available } unless llm_available?

        prompt = build_fix_prompt(tool_name: tool_name, error: last_error)
        result = llm_ask(prompt)
        return { success: false, reason: :llm_failed } unless result

        {
          success:         true,
          type:            :fix_suggestion,
          tool_name:       tool_name,
          suggestion:      result,
          requires_review: true
        }
      end

      def generate_tool_for_candidate(intent_text:, tool_chain:)
        return { success: false, reason: :llm_not_available } unless llm_available?

        spec = generate_tool_spec(intent: intent_text, existing_chain: tool_chain)
        return spec unless spec[:success]

        register_generated_pattern(spec[:tool_spec], intent_text)

        spec
      end

      def generate_tool_spec(intent:, existing_chain: nil)
        prompt = build_generation_prompt(intent: intent, existing_chain: existing_chain)
        result = llm_ask(prompt)
        return { success: false, reason: :llm_failed } unless result

        parsed = parse_tool_spec(result)
        return { success: false, reason: :parse_failed, raw: result } unless parsed

        { success: true, tool_spec: parsed }
      end

      def validate_spec(spec)
        errors = []
        errors << 'missing name'            unless spec[:name]&.length&.positive?
        errors << 'missing description'     unless spec[:description]&.length&.positive?
        errors << 'missing runner_function' unless spec[:runner_function]&.length&.positive?

        if errors.empty?
          { success: true, tool_spec: spec, valid: true }
        else
          { success: false, reason: :invalid_spec, errors: errors, tool_spec: spec }
        end
      end

      def llm_available?
        !!(defined?(Legion::LLM) && Legion::LLM.respond_to?(:chat))
      end

      def llm_ask(prompt)
        return nil unless llm_available?

        response = Legion::LLM.chat(
          message: prompt,
          caller:  { source: 'legion-mcp', component: 'function_generator' }
        )
        response&.content
      rescue StandardError => e
        Legion::Logging.warn("FunctionGenerator LLM call failed: #{e.message}") if defined?(Legion::Logging)
        nil
      end

      def build_generation_prompt(intent:, existing_chain: nil)
        chain_context = existing_chain ? "\nExisting tool chain that partially handles this: #{existing_chain.inspect}" : ''

        <<~PROMPT
          Generate a tool specification for a LegionIO MCP tool that handles this user intent:
          "#{intent}"
          #{chain_context}
          Respond with ONLY a JSON object (no markdown, no explanation):
          {
            "name": "legion.tool_name",
            "description": "What this tool does",
            "runner_function": "extension_name/runner_name/method_name",
            "parameters": [{"name": "param1", "type": "string", "required": true, "description": "..."}],
            "category": "one of: query, action, analysis, utility"
          }
        PROMPT
      end

      def build_fix_prompt(tool_name:, error:)
        <<~PROMPT
          The MCP tool "#{tool_name}" has a high failure rate. Last error: #{error}
          Suggest a fix or replacement approach. Respond concisely (2-3 sentences max).
        PROMPT
      end

      def parse_tool_spec(raw)
        json_match = raw.match(/\{[\s\S]*\}/)
        return nil unless json_match

        parsed = ::JSON.parse(json_match[0], symbolize_names: true)
        return nil unless parsed.is_a?(Hash) && parsed[:name]

        parsed
      rescue ::JSON::ParserError
        nil
      end

      def register_generated_pattern(spec, intent_text)
        return unless defined?(PatternStore)

        normalized   = intent_text.to_s.strip.downcase.gsub(/\s+/, ' ')
        intent_hash  = Digest::SHA256.hexdigest(normalized)

        PatternStore.promote_candidate(
          intent_hash: intent_hash,
          tool_chain:  [spec[:runner_function] || spec[:name]],
          intent_text: intent_text
        )
      rescue StandardError => e
        Legion::Logging.warn("register_generated_pattern failed: #{e.message}") if defined?(Legion::Logging)
      end
    end
  end
end
