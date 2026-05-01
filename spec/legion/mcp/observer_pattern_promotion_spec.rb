# frozen_string_literal: true

require 'spec_helper'
require 'legion/mcp/observer'
require 'legion/mcp/patterns/store'

RSpec.describe 'Observer pattern promotion' do
  before do
    Legion::MCP::Observer.reset!
    Legion::MCP::Patterns::Store.reset!
  end

  it 'promotes a candidate after 3 identical intent+tool observations' do
    3.times do
      Legion::MCP::Observer.record_intent_with_result(
        intent:    'check deploy status',
        tool_name: 'legion.get_status',
        success:   true
      )
    end

    hash = Digest::SHA256.hexdigest('check deploy status')
    pattern = Legion::MCP::Patterns::Store.lookup(hash)
    expect(pattern).not_to be_nil
    expect(pattern[:confidence]).to eq(0.5)
    expect(pattern[:tool_chain]).to eq(['legion.get_status'])
  end

  it 'does not promote before threshold' do
    2.times do
      Legion::MCP::Observer.record_intent_with_result(
        intent:    'check deploy status',
        tool_name: 'legion.get_status',
        success:   true
      )
    end

    hash = Digest::SHA256.hexdigest('check deploy status')
    expect(Legion::MCP::Patterns::Store.lookup(hash)).to be_nil
  end

  it 'does not promote failed intents' do
    3.times do
      Legion::MCP::Observer.record_intent_with_result(
        intent:    'failing action',
        tool_name: 'legion.get_status',
        success:   false
      )
    end

    hash = Digest::SHA256.hexdigest('failing action')
    expect(Legion::MCP::Patterns::Store.lookup(hash)).to be_nil
  end
end
