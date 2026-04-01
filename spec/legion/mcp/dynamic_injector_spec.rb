# frozen_string_literal: true

require 'spec_helper'
require 'legion/mcp'

RSpec.describe Legion::MCP::DynamicInjector do
  let(:always_tool) do
    Class.new(MCP::Tool) do
      tool_name 'legion.do'
      description 'Entry point.'
      input_schema(properties: {})
    end
  end

  let(:deferred_tool) do
    Class.new(MCP::Tool) do
      tool_name 'legion.ask_peer'
      description 'Ask a peer.'
      input_schema(properties: { peer: { type: 'string' } })
    end
  end

  before do
    allow(Legion::Settings).to receive(:dig).and_return(nil)
  end

  describe '.enabled?' do
    it 'returns false by default' do
      expect(described_class.enabled?).to be false
    end

    it 'returns true when enabled in settings' do
      allow(Legion::Settings).to receive(:dig).with(:mcp, :dynamic_tools, :enabled).and_return(true)
      expect(described_class.enabled?).to be true
    end
  end

  describe '.max_injected' do
    it 'defaults to 10' do
      expect(described_class.max_injected).to eq(10)
    end

    it 'reads from settings' do
      allow(Legion::Settings).to receive(:dig).with(:mcp, :dynamic_tools, :max_injected).and_return(5)
      expect(described_class.max_injected).to eq(5)
    end
  end

  describe '.context_tools' do
    context 'when disabled' do
      it 'returns empty array' do
        expect(described_class.context_tools('check mesh status')).to eq([])
      end
    end

    context 'when enabled' do
      before do
        allow(Legion::Settings).to receive(:dig).with(:mcp, :dynamic_tools, :enabled).and_return(true)
        allow(Legion::Settings).to receive(:dig).with(:mcp, :dynamic_tools, :max_injected).and_return(10)
        allow(Legion::Settings).to receive(:dig).with(:mcp, :deferred_loading, :enabled).and_return(true)
        allow(Legion::Settings).to receive(:dig).with(:mcp, :deferred_loading, :always_loaded).and_return(nil)
        allow(Legion::MCP::Server).to receive(:tool_registry).and_return([always_tool, deferred_tool])
      end

      it 'returns context-relevant tools excluding always-loaded' do
        allow(Legion::MCP::ContextCompiler).to receive(:match_tools).and_return(
          [{ name: 'legion.ask_peer', description: 'Ask a peer.', score: 3 }]
        )
        result = described_class.context_tools('ask a peer')
        expect(result.map(&:tool_name)).to include('legion.ask_peer')
      end

      it 'excludes always-loaded tools from results' do
        allow(Legion::MCP::ContextCompiler).to receive(:match_tools).and_return(
          [{ name: 'legion.do', description: 'Entry point.', score: 5 }]
        )
        result = described_class.context_tools('do something')
        expect(result.map(&:tool_name)).not_to include('legion.do')
      end

      it 'returns empty for nil intent' do
        expect(described_class.context_tools(nil)).to eq([])
      end

      it 'returns empty for blank intent' do
        expect(described_class.context_tools('   ')).to eq([])
      end

      it 'excludes zero-score matches' do
        allow(Legion::MCP::ContextCompiler).to receive(:match_tools).and_return(
          [{ name: 'legion.ask_peer', description: 'Ask a peer.', score: 0 }]
        )
        result = described_class.context_tools('unrelated query')
        expect(result).to be_empty
      end
    end
  end

  describe '.tools_changed?' do
    it 'returns true when tool sets differ' do
      expect(described_class.tools_changed?(%w[a b], %w[a c])).to be true
    end

    it 'returns false when tool sets are identical' do
      expect(described_class.tools_changed?(%w[a b], %w[b a])).to be false
    end

    it 'returns true when sizes differ' do
      expect(described_class.tools_changed?(%w[a], %w[a b])).to be true
    end
  end

  describe '.notify_if_changed' do
    let(:server) { instance_double(MCP::Server) }

    it 'sends notification when tools changed' do
      allow(server).to receive(:respond_to?).with(:notify_tools_list_changed).and_return(true)
      expect(server).to receive(:notify_tools_list_changed)
      described_class.notify_if_changed(server, %w[a], %w[a b])
    end

    it 'does not send notification when tools unchanged' do
      expect(server).not_to receive(:notify_tools_list_changed)
      described_class.notify_if_changed(server, %w[a b], %w[b a])
    end
  end

  describe '.inject_for_context' do
    let(:server) { instance_double(MCP::Server) }

    context 'when disabled' do
      it 'returns previous_names unchanged' do
        result = described_class.inject_for_context(server, 'some intent', previous_names: %w[a])
        expect(result).to eq(%w[a])
      end
    end
  end
end
