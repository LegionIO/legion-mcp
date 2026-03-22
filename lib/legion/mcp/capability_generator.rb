# frozen_string_literal: true

module Legion
  module MCP
    module CapabilityGenerator
      module_function

      def generate_from_gap(gap)
        name = infer_name(gap)
        description = infer_description(gap)

        proposal = {
          name:         name,
          description:  description,
          source_gap:   gap,
          runner_code:  nil,
          spec_code:    nil,
          confidence:   :sandbox,
          generated_at: Time.now
        }

        if llm_available?
          proposal[:runner_code] = generate_runner(name, description, gap)
          proposal[:spec_code] = generate_spec(name, description)
        end

        proposal
      rescue StandardError => e
        Legion::Logging.warn("CapabilityGenerator#generate_from_gap failed: #{e.message}") if defined?(Legion::Logging)
        { error: e.message, source_gap: gap }
      end

      def validate(runner_code:, spec_code:) # rubocop:disable Lint/UnusedMethodArgument
        result = { syntax_valid: false, eval_score: nil }

        result[:syntax_valid] = syntax_valid?(runner_code) if runner_code

        if runner_code && defined?(Legion::Extensions::Eval::Client)
          begin
            client = Legion::Extensions::Eval::Client.new
            eval_result = client.evaluate(code: runner_code, criteria: 'code_quality')
            result[:eval_score] = eval_result[:score] if eval_result[:success]
          rescue StandardError => e
            Legion::Logging.warn("CapabilityGenerator#validate eval failed: #{e.message}") if defined?(Legion::Logging)
            nil
          end
        end

        result
      end

      def infer_name(gap)
        case gap[:type]
        when :frequent_intent
          gap[:sample_intents].first.to_s.gsub(/\s+/, '_').downcase.slice(0, 30)
        when :repeated_chain
          gap[:chain].join('_then_').slice(0, 30)
        else
          "generated_#{Time.now.to_i}"
        end
      end

      def infer_description(gap)
        case gap[:type]
        when :frequent_intent
          "Auto-generated from #{gap[:count]} observed intents: #{gap[:sample_intents].first(3).join(', ')}"
        when :repeated_chain
          "Auto-generated from #{gap[:count]} observed sequences: #{gap[:chain].join(' -> ')}"
        else
          'Auto-generated capability'
        end
      end

      def generate_runner(name, description, _gap)
        return nil unless llm_available?

        prompt = "Generate a Ruby module for a LegionIO runner named '#{name}'. " \
                 "Description: #{description}. " \
                 'Follow the pattern: module with module_function methods returning hashes. ' \
                 'Include proper error handling. Return ONLY the Ruby code.'

        Legion::LLM.ask(prompt)
      rescue StandardError => e
        Legion::Logging.warn("CapabilityGenerator#generate_runner failed: #{e.message}") if defined?(Legion::Logging)
        nil
      end

      def generate_spec(name, description)
        return nil unless llm_available?

        prompt = "Generate RSpec tests for a Ruby module named '#{name}'. " \
                 "Description: #{description}. " \
                 'Use described_class pattern. Return ONLY the Ruby code.'

        Legion::LLM.ask(prompt)
      rescue StandardError => e
        Legion::Logging.warn("CapabilityGenerator#generate_spec failed: #{e.message}") if defined?(Legion::Logging)
        nil
      end

      def syntax_valid?(code)
        RubyVM::InstructionSequence.compile(code)
        true
      rescue SyntaxError => e
        Legion::Logging.debug("CapabilityGenerator#syntax_valid? syntax error: #{e.message}") if defined?(Legion::Logging)
        false
      end

      def llm_available?
        defined?(Legion::LLM) && Legion::LLM.respond_to?(:started?) && Legion::LLM.started?
      end
    end
  end
end
