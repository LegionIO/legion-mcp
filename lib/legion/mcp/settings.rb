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
          codegen:         {
            self_generate: {
              enabled:            false,
              cooldown_seconds:   300,
              max_gaps_per_cycle: 5,
              tier:               {
                simple_max_occurrences:    10,
                complex_min_occurrences:   11,
                recurrence_window_seconds: 86_400
              },
              runner_method:      {
                output_dir: '~/.legionio/generated/runners',
                namespace:  'Legion::Generated'
              },
              full_extension:     {
                output_dir:  '~/.legionio/generated/extensions',
                auto_bundle: false
              },
              validation:         {
                syntax_check: true,
                run_specs:    true,
                llm_review:   true,
                max_retries:  2,
                quality_gate: {
                  enabled:   false,
                  threshold: 0.8
                }
              },
              approval:           {
                required:                false,
                auto_approve_confidence: 0.9,
                auto_approve_gap_types:  []
              },
              hot_register:       {
                mcp_tools:          true,
                full_load_on_boot:  true
              },
              corroboration:      {
                enabled:                      true,
                min_agents:                   2,
                apollo_query_before_generate: true,
                priority_boost_per_agent:     0.15
              },
              github:             {
                enabled:               false,
                auto_branch:           true,
                auto_pr:               true,
                auto_merge:            false,
                target_repo:           nil,
                target_branch:         'main',
                pr_labels:             %w[auto-generated needs-review],
                adversarial_reviewers: 3
              }
            }
          },
          mcp:             {
            auto_expose_runners: false
          }
        }
      end
    end
  end
end
