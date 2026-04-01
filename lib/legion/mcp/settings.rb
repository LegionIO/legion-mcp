# frozen_string_literal: true

module Legion
  module MCP
    module Settings
      module_function

      def defaults
        {
          servers:         {},
          overrides:       {},
          tool_cache_ttl:  300,
          connect_timeout: 10,
          call_timeout:    30,
          codegen:         { self_generate: self_generate_defaults },
          mcp:             { auto_expose_runners: false, deferred_loading: deferred_loading_defaults }
        }
      end

      def deferred_loading_defaults
        { enabled: true, always_loaded: [] }
      end

      def self_generate_defaults
        {
          enabled:            false,
          cooldown_seconds:   300,
          max_gaps_per_cycle: 5,
          tier:               self_generate_tier_defaults,
          runner_method:      { output_dir: '~/.legionio/generated/runners', namespace: 'Legion::Generated' },
          full_extension:     { output_dir: '~/.legionio/generated/extensions', auto_bundle: false },
          validation:         self_generate_validation_defaults,
          approval:           { required: false, auto_approve_confidence: 0.9, auto_approve_gap_types: [] },
          hot_register:       { mcp_tools: true, full_load_on_boot: true },
          corroboration:      self_generate_corroboration_defaults,
          github:             self_generate_github_defaults
        }
      end

      def self_generate_tier_defaults
        {
          simple_max_occurrences:    10,
          complex_min_occurrences:   11,
          recurrence_window_seconds: 86_400
        }
      end

      def self_generate_validation_defaults
        {
          syntax_check: true,
          run_specs:    true,
          llm_review:   true,
          max_retries:  2,
          quality_gate: { enabled: false, threshold: 0.8 }
        }
      end

      def self_generate_corroboration_defaults
        {
          enabled:                      true,
          min_agents:                   2,
          apollo_query_before_generate: true,
          priority_boost_per_agent:     0.15
        }
      end

      def self_generate_github_defaults
        {
          enabled:               false,
          auto_branch:           true,
          auto_pr:               true,
          auto_merge:            false,
          target_repo:           nil,
          target_branch:         'main',
          pr_labels:             %w[auto-generated needs-review],
          adversarial_reviewers: 3
        }
      end
    end
  end
end
