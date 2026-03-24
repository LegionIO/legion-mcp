# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'MCP Client boot' do
  it 'loads server registry from settings at boot' do
    Legion::MCP::Client::ServerRegistry.reset!
    settings = {
      'filesystem' => { transport: :stdio, command: 'npx server-filesystem /tmp' },
      'github'     => { transport: :http, url: 'http://localhost:8080/mcp' }
    }
    allow(Legion::Settings).to receive(:dig).with(:mcp, :servers).and_return(settings)

    Legion::MCP::Client.boot
    servers = Legion::MCP::Client::ServerRegistry.servers
    expect(servers).to have_key('filesystem')
    expect(servers).to have_key('github')
  end

  it 'does nothing when no servers configured' do
    Legion::MCP::Client::ServerRegistry.reset!
    allow(Legion::Settings).to receive(:dig).with(:mcp, :servers).and_return(nil)

    Legion::MCP::Client.boot
    expect(Legion::MCP::Client::ServerRegistry.servers).to be_empty
  end
end
