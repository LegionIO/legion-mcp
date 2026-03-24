# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'MCP Client settings schema' do
  it 'provides default settings with required keys' do
    defaults = Legion::MCP::Settings.defaults
    expect(defaults).to have_key(:servers)
    expect(defaults).to have_key(:overrides)
    expect(defaults).to have_key(:tool_cache_ttl)
    expect(defaults).to have_key(:connect_timeout)
    expect(defaults).to have_key(:call_timeout)
  end

  it 'has sensible defaults' do
    defaults = Legion::MCP::Settings.defaults
    expect(defaults[:servers]).to eq({})
    expect(defaults[:overrides]).to eq({})
    expect(defaults[:tool_cache_ttl]).to eq(300)
    expect(defaults[:connect_timeout]).to eq(10)
    expect(defaults[:call_timeout]).to eq(30)
  end
end
