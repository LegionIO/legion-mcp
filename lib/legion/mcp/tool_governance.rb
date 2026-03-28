# frozen_string_literal: true

module Legion
  module MCP
    module ToolGovernance
      RISK_TIER_ORDER = { low: 0, medium: 1, high: 2, critical: 3 }.freeze

      DEFAULT_TOOL_TIERS = {
        'legion.list_workers'      => :low,
        'legion.show_worker'       => :low,
        'legion.list_tasks'        => :low,
        'legion.get_task'          => :low,
        'legion.get_status'        => :low,
        'legion.get_config'        => :low,
        'legion.describe_runner'   => :low,
        'legion.list_extensions'   => :low,
        'legion.run_task'          => :medium,
        'legion.create_schedule'   => :medium,
        'legion.worker_lifecycle'  => :high,
        'legion.enable_extension'  => :high,
        'legion.disable_extension' => :high,
        'legion.delete_task'       => :high,
        'legion.rbac_assignments'  => :high,
        'legion.rbac_grants'       => :high
      }.freeze

      module_function

      def filter_tools(tools, identity)
        return tools unless governance_enabled?

        risk_tier = identity&.dig(:risk_tier) || :low
        tier_value = RISK_TIER_ORDER[risk_tier] || 0

        # DEFAULT_TOOL_TIERS is the fallback; custom_tiers (from Settings) override it;
        # definition-level mcp_tier on the tool class takes highest precedence.
        fallback_tiers = DEFAULT_TOOL_TIERS.merge(custom_tiers)
        tools.select do |tool|
          tool_tier = definition_tier(tool) || fallback_tiers[tool_name(tool)] || :low
          (RISK_TIER_ORDER[tool_tier] || 0) <= tier_value
        end
      end

      def audit_invocation(tool_name:, identity:, params:, result:)
        return unless audit_enabled? && defined?(Legion::Audit)

        Legion::Audit.record(
          event_type:   'mcp_tool_invocation',
          principal_id: identity&.dig(:worker_id) || identity&.dig(:user_id) || 'unknown',
          action:       "mcp.#{tool_name}",
          resource:     'mcp_tool',
          detail:       { param_keys: params&.keys, success: !result&.dig(:error) }
        )
      end

      def governance_enabled?
        Legion::Settings.dig(:mcp, :governance, :enabled) == true
      end

      def audit_enabled?
        Legion::Settings.dig(:mcp, :governance, :audit_invocations) != false
      end

      def custom_tiers
        Legion::Settings.dig(:mcp, :governance, :tool_risk_tiers) || {}
      end

      def tool_name(tool)
        if tool.respond_to?(:tool_name)
          tool.tool_name
        elsif tool.respond_to?(:name)
          tool.name
        else
          tool.to_s
        end
      end

      # Returns the mcp_tier declared on the tool class via the definition DSL, or nil if absent.
      # Tool classes built by FunctionDiscovery expose mcp_tier as a singleton method.
      def definition_tier(tool)
        return nil unless tool.respond_to?(:mcp_tier)

        tier = tool.mcp_tier
        return nil if tier.nil?

        normalized = tier.to_s.downcase.to_sym
        return nil unless RISK_TIER_ORDER.key?(normalized)

        normalized
      end
    end
  end
end
