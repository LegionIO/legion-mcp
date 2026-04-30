# frozen_string_literal: true

module Legion
  module MCP
    module ToolGovernance
      extend Legion::Logging::Helper

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
        before = tools.size
        tools = filter_by_risk_tier(tools, identity&.dig(:risk_tier)) if governance_enabled?
        tools = filter_by_role(tools, identity[:role]) if identity.is_a?(Hash) && identity[:role]
        log.debug("[mcp][governance] action=filter_tools before=#{before} after=#{tools.size} " \
                  "governance_enabled=#{governance_enabled?} " \
                  "risk_tier=#{identity&.dig(:risk_tier)} role=#{identity.is_a?(Hash) ? identity[:role] : nil}")
        tools
      end

      def filter_by_risk_tier(tools, risk_tier)
        tier_value = RISK_TIER_ORDER[risk_tier || :low] || 0
        log.debug("[mcp][governance] action=filter_by_risk_tier risk_tier=#{risk_tier || :low} " \
                  "tier_value=#{tier_value} tools_in=#{tools.size}")

        # DEFAULT_TOOL_TIERS is the fallback; custom_tiers (from Settings) override it;
        # definition-level mcp_tier on the tool class takes highest precedence.
        # Tools without any tier metadata default to :medium so they are not
        # exposed to low-tier identities (safe-by-default).
        fallback_tiers = DEFAULT_TOOL_TIERS.merge(custom_tiers)
        result = tools.select do |tool|
          tool_tier = definition_tier(tool) || fallback_tiers[tool_name(tool)] || :medium
          (RISK_TIER_ORDER[tool_tier] || 0) <= tier_value
        end
        log.debug("[mcp][governance] action=filter_by_risk_tier.complete tools_out=#{result.size}")
        result
      end

      def filter_by_role(tools, role)
        return tools unless role

        allowed = role_allowlist(role)
        log.debug("[mcp][governance] action=filter_by_role role=#{role} " \
                  "allowlist_size=#{allowed.size} wildcard=#{allowed.include?('*')}")
        return tools if allowed.include?('*')

        result = tools.select do |tool|
          name = tool_name(tool).to_s
          allowed.any? { |pattern| File.fnmatch?(pattern, name) }
        end
        log.debug("[mcp][governance] action=filter_by_role.complete before=#{tools.size} after=#{result.size}")
        result
      end

      def role_allowlist(role)
        roles = Legion::Settings.dig(:mcp, :roles)
        return ['*'] unless roles.is_a?(Hash)

        role_config = roles[role.to_sym] || roles[role.to_s]
        return ['*'] unless role_config.is_a?(Hash)

        Array(role_config[:tools] || role_config['tools'])
      end

      def audit_invocation(tool_name:, identity:, params:, result:)
        return unless audit_enabled? && defined?(Legion::Audit)

        log.debug("[mcp][governance] action=audit_invocation tool_name=#{tool_name} " \
                  "user=#{identity&.dig(:user_id)}")
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
