# frozen_string_literal: true

require 'spec_helper'
require 'legion/mcp'

RSpec.describe Legion::MCP::StructuralIndex do
  before do
    allow(Legion::Settings).to receive(:dig).and_return(nil)
  end

  describe '.build' do
    it 'returns a hash with extensions, tools, and generated_at' do
      result = described_class.build
      expect(result).to have_key(:extensions)
      expect(result).to have_key(:tools)
      expect(result).to have_key(:generated_at)
    end

    it 'returns empty extensions when Legion::Extensions is not defined' do
      result = described_class.build
      expect(result[:extensions]).to eq([])
    end

    it 'includes MCP-specific tools from tool_registry' do
      result = described_class.build
      names = result[:tools].map { |t| t[:name] }
      expect(names).to include('legion.tools', 'legion.plan', 'legion.tool_audit')
    end
  end

  describe '.scan_tools' do
    it 'returns tool entries with name, description, catalog flag' do
      tools = described_class.scan_tools
      first = tools.first
      expect(first).to have_key(:name)
      expect(first).to have_key(:description)
      expect(first).to have_key(:catalog)
    end

    it 'marks standard tools as non-catalog' do
      tools = described_class.scan_tools
      plan = tools.find { |t| t[:name] == 'legion.plan' }
      expect(plan[:catalog]).to be false
    end
  end

  describe '.filter' do
    let(:index) do
      {
        extensions: [
          { name: 'lex-http', runners: [{ name: 'Request', functions: %w[get post] }], actors: [] },
          { name: 'lex-mesh', runners: [], actors: [{ name: 'Gossip', type: 'interval' }] }
        ],
        tools: [
          { name: 'legion.do', description: 'Do action', catalog: false },
          { name: 'legion.mesh_status', description: 'Mesh status', catalog: false }
        ],
        generated_at: '2026-03-31T00:00:00Z'
      }
    end

    it 'filters by extension name' do
      result = described_class.filter(index, extension: 'http')
      expect(result[:extensions].length).to eq(1)
      expect(result[:extensions].first[:name]).to eq('lex-http')
    end

    it 'filters by type tools' do
      result = described_class.filter(index, type: 'tools')
      expect(result).to have_key(:tools)
      expect(result).not_to have_key(:extensions)
    end

    it 'filters by type extensions' do
      result = described_class.filter(index, type: 'extensions')
      expect(result).to have_key(:extensions)
      expect(result).not_to have_key(:tools)
    end

    it 'filters by type runners' do
      result = described_class.filter(index, type: 'runners')
      ext = result[:extensions].first
      expect(ext).to have_key(:runners)
      expect(ext).not_to have_key(:actors)
    end

    it 'filters by type actors' do
      result = described_class.filter(index, type: 'actors')
      ext = result[:extensions].find { |e| e[:name] == 'lex-mesh' }
      expect(ext).to have_key(:actors)
      expect(ext).not_to have_key(:runners)
    end

    it 'returns full index with no filters' do
      result = described_class.filter(index)
      expect(result[:extensions].length).to eq(2)
      expect(result[:tools].length).to eq(2)
    end
  end

  describe '.cached' do
    it 'returns nil when cache file does not exist' do
      allow(File).to receive(:exist?).with(described_class::CACHE_PATH).and_return(false)
      expect(described_class.cached).to be_nil
    end
  end
end
