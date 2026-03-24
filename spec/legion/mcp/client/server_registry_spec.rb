# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Legion::MCP::Client::ServerRegistry do
  before { described_class.reset! }

  describe '.load_from_settings' do
    it 'registers servers from settings' do
      settings = {
        'filesystem' => { transport: :stdio, command: 'npx @modelcontextprotocol/server-filesystem /tmp' },
        'github'     => { transport: :http, url: 'http://localhost:8080/mcp' }
      }
      described_class.load_from_settings(settings)
      expect(described_class.servers).to have_key('filesystem')
      expect(described_class.servers).to have_key('github')
      expect(described_class.servers['filesystem'][:transport]).to eq(:stdio)
    end
  end

  describe '.register / .deregister' do
    it 'registers a server at runtime' do
      described_class.register('custom', transport: :http, url: 'http://example.com/mcp')
      expect(described_class.servers).to have_key('custom')
    end

    it 'deregisters a server' do
      described_class.register('custom', transport: :http, url: 'http://example.com/mcp')
      described_class.deregister('custom')
      expect(described_class.servers).not_to have_key('custom')
    end
  end

  describe '.healthy_servers' do
    it 'returns only servers marked healthy' do
      described_class.register('healthy', transport: :http, url: 'http://good.com/mcp')
      described_class.register('sick', transport: :http, url: 'http://bad.com/mcp')
      described_class.mark_unhealthy('sick')
      expect(described_class.healthy_servers.keys).to eq(['healthy'])
    end

    it 'recovers unhealthy servers after cooldown' do
      described_class.register('flaky', transport: :http, url: 'http://flaky.com/mcp')
      described_class.mark_unhealthy('flaky', cooldown: 0)
      expect(described_class.healthy_servers.keys).to include('flaky')
    end
  end

  describe '.reset!' do
    it 'clears all servers' do
      described_class.register('test', transport: :http, url: 'http://test.com')
      described_class.reset!
      expect(described_class.servers).to be_empty
    end
  end
end
