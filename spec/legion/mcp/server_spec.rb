# frozen_string_literal: true

require 'spec_helper'
require 'legion/mcp'

RSpec.describe Legion::MCP::Server do
  before { allow(Legion::Settings).to receive(:dig).and_return(nil) }

  describe '.build' do
    subject(:server) { described_class.build }

    it 'returns an MCP::Server instance' do
      expect(server).to be_a(MCP::Server)
    end

    it 'registers the correct name' do
      expect(server.name).to eq('legion')
    end

    it 'registers the correct version' do
      expect(server.version).to eq(Legion::VERSION)
    end

    it 'registers all tool classes' do
      expected = %w[
        legion.run_task legion.describe_runner
        legion.list_tasks legion.get_task legion.delete_task legion.get_task_logs
        legion.list_chains legion.create_chain legion.update_chain legion.delete_chain
        legion.list_relationships legion.create_relationship legion.update_relationship legion.delete_relationship
        legion.list_extensions legion.get_extension legion.enable_extension legion.disable_extension
        legion.list_schedules legion.create_schedule legion.update_schedule legion.delete_schedule
        legion.get_status legion.get_config
      ]
      expect(server.tools.keys).to include(*expected)
    end

    it 'registers exactly 56 tools' do
      expect(server.tools.size).to eq(56)
    end

    it 'includes instructions' do
      expect(server.instructions).to include('async job engine')
    end

    describe '.wire_observer' do
      before { Legion::MCP::Observer.reset! }

      it 'skips record_intent_with_result for legion.do calls' do
        expect(Legion::MCP::Observer).not_to receive(:record_intent_with_result)
        described_class.wire_observer(
          method: 'tools/call', tool_name: 'legion.do',
          duration: 0.01, tool_arguments: { intent: 'hello' }, error: nil
        )
      end

      it 'records intent_with_result for non-legion.do tools with intent' do
        expect(Legion::MCP::Observer).to receive(:record_intent_with_result).with(
          intent: 'check status', tool_name: 'legion.get_status', success: true
        )
        described_class.wire_observer(
          method: 'tools/call', tool_name: 'legion.get_status',
          duration: 0.01, tool_arguments: { intent: 'check status' }, error: nil
        )
      end
    end

    context 'with governance enabled' do
      before do
        allow(Legion::Settings).to receive(:dig).and_return(nil)
        allow(Legion::Settings).to receive(:dig).with(:mcp, :governance, :enabled).and_return(true)
        allow(Legion::Settings).to receive(:dig).with(:mcp, :governance, :tool_risk_tiers).and_return({})
      end

      it 'excludes high and medium tier tools for low-tier identity' do
        server = described_class.build(identity: { risk_tier: :low })
        high_tools = Legion::MCP::ToolGovernance::DEFAULT_TOOL_TIERS.select { |_, v| %i[high medium].include?(v) }.keys
        expect(server.tools.keys & high_tools).to be_empty
      end

      it 'includes high-tier tools for high-tier identity' do
        server = described_class.build(identity: { risk_tier: :high })
        expect(server.tools.keys).to include('legion.worker_lifecycle')
      end
    end
  end
end
