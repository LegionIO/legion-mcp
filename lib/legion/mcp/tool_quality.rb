# frozen_string_literal: true

module Legion
  module MCP
    module ToolQuality
      extend Legion::Logging::Helper

      MIN_DESCRIPTION_LENGTH = 20
      MIN_PARAM_DESCRIPTION_LENGTH = 5

      module_function

      def audit_all
        log.debug("[mcp][tool_quality] action=audit_all tools=#{Server.tool_registry.size}")
        Server.tool_registry.map { |tc| audit_tool(tc) }
      end

      def audit_tool(tool_class)
        issues = []
        issues.concat(check_description(tool_class))
        issues.concat(check_params(tool_class))

        {
          name:        tool_class.tool_name,
          description: tool_class.description,
          category:    resolve_category(tool_class),
          issues:      issues,
          quality:     issues.empty? ? :pass : :warn
        }
      end

      def check_description(tool_class)
        issues = []
        desc = tool_class.description.to_s
        issues << 'description missing' if desc.empty?
        issues << "description too short (#{desc.length} chars, min #{MIN_DESCRIPTION_LENGTH})" if desc.length < MIN_DESCRIPTION_LENGTH
        issues
      end

      def check_params(tool_class)
        issues = []
        raw_schema = tool_class.input_schema
        schema = raw_schema.is_a?(Hash) ? raw_schema : raw_schema.to_h
        properties = schema[:properties] || {}

        properties.each do |param_name, meta|
          meta_hash = meta.is_a?(Hash) ? meta : {}
          desc = meta_hash[:description].to_s
          issues << "param '#{param_name}' missing or short description" if desc.length < MIN_PARAM_DESCRIPTION_LENGTH
        end

        issues
      end

      def resolve_category(tool_class)
        return tool_class.mcp_category.to_sym if tool_class.respond_to?(:mcp_category) && tool_class.mcp_category

        ContextCompiler::CATEGORIES.each do |cat, config|
          return cat if config[:tools].include?(tool_class.tool_name)
        end

        EXPANDED_CATEGORIES.each do |cat, config|
          return cat if config[:tools].include?(tool_class.tool_name)
        end

        :uncategorized
      end

      def capability_matrix
        Server.tool_registry.map do |tc|
          raw_schema = tc.input_schema
          schema = raw_schema.is_a?(Hash) ? raw_schema : raw_schema.to_h
          properties = schema[:properties] || {}
          required = schema[:required] || []

          {
            name:        tc.tool_name,
            category:    resolve_category(tc),
            param_count: properties.size,
            required:    required.map(&:to_s),
            reads:       reads?(tc),
            writes:      writes?(tc),
            catalog:     tc.respond_to?(:catalog_entry) && tc.catalog_entry
          }
        end
      end

      def reads?(tool_class)
        name = tool_class.tool_name
        name.start_with?('legion.list_', 'legion.get_', 'legion.show_') ||
          name.include?('query') || name.include?('search') ||
          name.include?('status') || name.include?('health') ||
          name.include?('stats') || name.include?('describe')
      end

      def writes?(tool_class)
        name = tool_class.tool_name
        name.start_with?('legion.create_', 'legion.update_', 'legion.delete_') ||
          name.start_with?('legion.enable_', 'legion.disable_') ||
          name.include?('run') || name.include?('approve') ||
          name.include?('propose') || name.include?('absorb') ||
          name.include?('broadcast') || name.include?('notify')
      end

      def summary
        results = audit_all
        pass_count = results.count { |r| r[:quality] == :pass }
        warn_count = results.count { |r| r[:quality] == :warn }
        categories = results.group_by { |r| r[:category] }

        {
          total_tools: results.size,
          passing:     pass_count,
          warnings:    warn_count,
          by_category: categories.transform_values(&:size),
          issues:      results.select { |r| r[:quality] == :warn }
        }
      end

      EXPANDED_CATEGORIES = {
        knowledge:   {
          tools:   %w[legion.query_knowledge legion.knowledge_health legion.knowledge_context legion.absorb],
          summary: 'Knowledge base operations — query, health, context retrieval, content absorption.'
        },
        mesh:        {
          tools:   %w[legion.ask_peer legion.list_peers legion.notify_peer legion.broadcast_peers legion.mesh_status],
          summary: 'Agent mesh communication — peer queries, notifications, broadcasts, and mesh topology.'
        },
        mind_growth: {
          tools:   %w[legion.mind_growth_status legion.mind_growth_propose legion.mind_growth_approve
                      legion.mind_growth_build_queue legion.mind_growth_cognitive_profile legion.mind_growth_health],
          summary: 'Cognitive growth — proposals, approvals, build queue, cognitive profiling, fitness scores.'
        },
        prompts:     {
          tools:   %w[legion.prompt_list legion.prompt_show legion.prompt_run],
          summary: 'Prompt template management — list, view, and render prompt templates.'
        },
        datasets:    {
          tools:   %w[legion.dataset_list legion.dataset_show legion.experiment_results],
          summary: 'Dataset and experiment browsing — list datasets, view rows, compare experiment results.'
        },
        evals:       {
          tools:   %w[legion.eval_list legion.eval_run legion.eval_results],
          summary: 'Evaluation management — list evaluators, run evaluations, view results.'
        },
        meta:        {
          tools:   %w[legion.do legion.tools legion.plan_action legion.structural_index],
          summary: 'Meta-tools — natural language routing, tool discovery, planning, structural index.'
        }
      }.freeze
    end
  end
end
