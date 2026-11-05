# frozen_string_literal: true

require 'spec_helper'
require 'legion/mcp/tool_governance'

RSpec.describe Legion::MCP::ToolGovernance do
  before { Legion::Settings[:mcp][:governance] = { enabled: false, audit_invocations: true, tool_risk_tiers: {} } }

  let(:low_tool) { double('tool', tool_name: 'legion.list_tasks') }
  let(:high_tool) { double('tool', tool_name: 'legion.worker_lifecycle') }
  let(:medium_tool) { double('tool', tool_name: 'legion.run_task') }

  describe '.filter_tools' do
    context 'when governance is disabled' do
      it 'returns all tools unfiltered when no role is set' do
        tools = [low_tool, high_tool, medium_tool]
        expect(described_class.filter_tools(tools, {})).to eq(tools)
      end

      it 'returns all tools when identity is nil' do
        tools = [low_tool, high_tool, medium_tool]
        expect(described_class.filter_tools(tools, nil)).to eq(tools)
      end
    end

    context 'when governance is enabled' do
      before do
        Legion::Settings[:mcp][:governance][:enabled] = true
      end

      it 'filters tools for low-tier identity' do
        identity = { risk_tier: :low }
        result = described_class.filter_tools([low_tool, high_tool, medium_tool], identity)
        expect(result).to contain_exactly(low_tool)
      end

      it 'allows medium tools for medium-tier identity' do
        identity = { risk_tier: :medium }
        result = described_class.filter_tools([low_tool, high_tool, medium_tool], identity)
        expect(result).to contain_exactly(low_tool, medium_tool)
      end

      it 'allows all tools for high-tier identity' do
        identity = { risk_tier: :high }
        result = described_class.filter_tools([low_tool, high_tool, medium_tool], identity)
        expect(result).to contain_exactly(low_tool, high_tool, medium_tool)
      end

      it 'defaults to low tier for nil identity' do
        result = described_class.filter_tools([low_tool, high_tool], nil)
        expect(result).to contain_exactly(low_tool)
      end
    end
  end

  describe '.definition_tier' do
    it 'returns nil for a tool with no mcp_tier method' do
      tool = double('tool')
      expect(described_class.definition_tier(tool)).to be_nil
    end

    it 'returns nil when mcp_tier returns nil' do
      tool = double('tool', mcp_tier: nil)
      expect(described_class.definition_tier(tool)).to be_nil
    end

    it 'returns the tier as a symbol when mcp_tier is set' do
      tool = double('tool', mcp_tier: :high)
      expect(described_class.definition_tier(tool)).to eq(:high)
    end

    it 'coerces string tier to symbol' do
      tool = double('tool', mcp_tier: 'medium')
      expect(described_class.definition_tier(tool)).to eq(:medium)
    end
  end

  describe '.filter_tools with definition-level tiers' do
    context 'when governance is enabled' do
      before do
        Legion::Settings[:mcp][:governance][:enabled] = true
      end

      it 'prefers definition mcp_tier over DEFAULT_TOOL_TIERS' do
        # legion.list_tasks is :low in DEFAULT_TOOL_TIERS but definition says :high
        overridden_tool = double('tool', tool_name: 'legion.list_tasks', mcp_tier: :high)
        identity = { risk_tier: :medium }
        result = described_class.filter_tools([overridden_tool], identity)
        # :high > :medium so the tool should be excluded
        expect(result).to be_empty
      end

      it 'falls back to DEFAULT_TOOL_TIERS when mcp_tier is nil' do
        tool_without_def = double('tool', tool_name: 'legion.list_tasks', mcp_tier: nil)
        identity = { risk_tier: :low }
        result = described_class.filter_tools([tool_without_def], identity)
        expect(result).to contain_exactly(tool_without_def)
      end

      it 'defaults untiered tools to :medium so low-tier identities cannot access them' do
        untiered_tool = double('tool', tool_name: 'legion.custom_unknown_tool')
        identity = { risk_tier: :low }
        result = described_class.filter_tools([untiered_tool], identity)
        expect(result).to be_empty
      end

      it 'allows untiered tools for medium-tier identities' do
        untiered_tool = double('tool', tool_name: 'legion.custom_unknown_tool')
        identity = { risk_tier: :medium }
        result = described_class.filter_tools([untiered_tool], identity)
        expect(result).to contain_exactly(untiered_tool)
      end

      it 'allows untiered tools for high-tier identities' do
        untiered_tool = double('tool', tool_name: 'legion.custom_unknown_tool')
        identity = { risk_tier: :high }
        result = described_class.filter_tools([untiered_tool], identity)
        expect(result).to contain_exactly(untiered_tool)
      end
    end
  end

  describe '.filter_by_role' do
    let(:query_tool) { double('tool', tool_name: 'legion.query_knowledge') }
    let(:search_tool) { double('tool', tool_name: 'legion.search_sessions') }
    let(:list_tool) { double('tool', tool_name: 'legion.list_extensions') }
    let(:describe_tool) { double('tool', tool_name: 'legion.describe_runner') }
    let(:run_tool) { double('tool', tool_name: 'legion.run_task') }
    let(:all_tools) { [query_tool, search_tool, list_tool, describe_tool, run_tool] }

    it 'returns all tools when role is nil' do
      expect(described_class.filter_by_role(all_tools, nil)).to eq(all_tools)
    end

    context 'with researcher role' do
      let(:researcher_roles) do
        {
          researcher: { tools: ['legion.query_knowledge', 'legion.search_*', 'legion.list_*'] }
        }
      end

      before do
        Legion::Settings[:mcp][:roles] = researcher_roles
      end

      it 'returns only tools matching the allowlist patterns' do
        result = described_class.filter_by_role(all_tools, :researcher)
        expect(result).to contain_exactly(query_tool, search_tool, list_tool)
      end

      it 'excludes tools not in the allowlist' do
        result = described_class.filter_by_role(all_tools, :researcher)
        expect(result).not_to include(run_tool, describe_tool)
      end
    end

    context 'with orchestrator role (wildcard)' do
      before do
        Legion::Settings[:mcp][:roles] = { orchestrator: { tools: ['*'] } }
      end

      it 'returns all tools when allowlist contains wildcard' do
        result = described_class.filter_by_role(all_tools, :orchestrator)
        expect(result).to eq(all_tools)
      end
    end

    context 'with glob patterns' do
      before do
        Legion::Settings[:mcp][:roles] = { reviewer: { tools: ['legion.list_*', 'legion.describe_*', 'legion.query_*'] } }
      end

      it 'matches glob patterns correctly' do
        result = described_class.filter_by_role(all_tools, :reviewer)
        expect(result).to contain_exactly(query_tool, list_tool, describe_tool)
      end
    end

    context 'with sub_agent role (exact matches only)' do
      before do
        Legion::Settings[:mcp][:roles] = { sub_agent: { tools: ['legion.query_knowledge', 'legion.retrieve_knowledge'] } }
      end

      it 'restricts to exact tool names' do
        result = described_class.filter_by_role(all_tools, :sub_agent)
        expect(result).to contain_exactly(query_tool)
      end
    end

    context 'when role is not configured' do
      before do
        Legion::Settings[:mcp][:roles] = { researcher: { tools: ['legion.query_knowledge'] } }
      end

      it 'returns all tools for an unknown role' do
        result = described_class.filter_by_role(all_tools, :unknown_role)
        expect(result).to eq(all_tools)
      end
    end

    context 'when roles config is missing' do
      before do
        Legion::Settings[:mcp].delete(:roles)
      end

      it 'returns all tools' do
        result = described_class.filter_by_role(all_tools, :researcher)
        expect(result).to eq(all_tools)
      end
    end

    context 'with string role key' do
      before do
        Legion::Settings[:mcp][:roles] = { 'researcher' => { 'tools' => ['legion.query_knowledge'] } }
      end

      it 'matches string role keys' do
        result = described_class.filter_by_role(all_tools, :researcher)
        expect(result).to contain_exactly(query_tool)
      end
    end

    it 'retains string-key fallback for nil values without widening permissions' do
      Legion::Settings[:mcp][:roles] = { researcher: nil, 'researcher' => { tools: nil, 'tools' => ['legion.query_knowledge'] } }

      expect(described_class.filter_by_role(all_tools, :researcher)).to contain_exactly(query_tool)
    end

    it 'denies an explicitly disabled role without using a string-key wildcard fallback' do
      Legion::Settings[:mcp][:roles] = { researcher: false, 'researcher' => { tools: ['*'] } }

      expect(described_class.filter_by_role(all_tools, :researcher)).to be_empty
    end

    it 'denies explicitly disabled tools without using a string-key wildcard fallback' do
      Legion::Settings[:mcp][:roles] = { researcher: { tools: false, 'tools' => ['*'] } }

      expect(described_class.filter_by_role(all_tools, :researcher)).to be_empty
    end

    it 'reads changed permissions from the current settings tree' do
      Legion::Settings[:mcp][:roles] = { researcher: { tools: ['legion.query_knowledge'] } }
      expect(described_class.filter_by_role(all_tools, :researcher)).to contain_exactly(query_tool)

      Legion::Settings[:mcp][:roles] = { researcher: { tools: [] } }
      expect(described_class.filter_by_role(all_tools, :researcher)).to be_empty
    end
  end

  describe '.filter_tools with role and risk tier composed' do
    let(:query_tool) { double('tool', tool_name: 'legion.query_knowledge') }
    let(:search_tool) { double('tool', tool_name: 'legion.search_sessions') }

    context 'when governance is enabled and role is set' do
      before do
        Legion::Settings[:mcp][:governance][:enabled] = true
        Legion::Settings[:mcp][:roles] = { researcher: { tools: ['legion.query_knowledge'] } }
      end

      it 'applies both risk tier and role filtering' do
        # low_tool passes risk tier but not role; query_tool passes both
        # query_tool is untiered so defaults to :medium — use medium identity to pass risk tier
        identity = { risk_tier: :medium, role: :researcher }
        result = described_class.filter_tools([low_tool, query_tool], identity)
        # low_tool (legion.list_tasks) passes risk tier (:low <= :medium) but not role
        # query_tool (legion.query_knowledge) passes risk tier (default :medium <= :medium) and role
        expect(result).to contain_exactly(query_tool)
      end

      it 'filters by risk tier first then role narrows further' do
        identity = { risk_tier: :high, role: :researcher }
        result = described_class.filter_tools([low_tool, high_tool, query_tool], identity)
        # All pass risk tier (:high allows everything), but role filters to query_knowledge only
        expect(result).to contain_exactly(query_tool)
      end
    end

    context 'when governance is disabled but role is set' do
      before do
        Legion::Settings[:mcp][:roles] = { researcher: { tools: ['legion.search_*'] } }
      end

      it 'skips risk tier but still applies role filtering' do
        identity = { role: :researcher }
        result = described_class.filter_tools([low_tool, high_tool, search_tool], identity)
        expect(result).to contain_exactly(search_tool)
      end
    end
  end

  describe '.filter_tools role-based invocation blocking' do
    let(:query_tool) { double('tool', tool_name: 'legion.query_knowledge') }
    let(:blocked_tool) { double('tool', tool_name: 'legion.run_task') }

    before do
      Legion::Settings[:mcp][:roles] = { sub_agent: { tools: ['legion.query_knowledge'] } }
    end

    it 'blocks tools not in the role allowlist' do
      identity = { role: :sub_agent }
      result = described_class.filter_tools([query_tool, blocked_tool], identity)
      expect(result).not_to include(blocked_tool)
    end

    it 'allows tools in the role allowlist' do
      identity = { role: :sub_agent }
      result = described_class.filter_tools([query_tool, blocked_tool], identity)
      expect(result).to include(query_tool)
    end
  end
end
