# frozen_string_literal: true

require 'spec_helper'
require 'legion/mcp'

RSpec.describe 'MCP Server reset on Catalog change' do
  before { allow(Legion::Settings).to receive(:dig).and_return(nil) }

  describe '.register_catalog_listener' do
    it 'calls Legion::MCP.reset! when Catalog changes' do
      # Stub the registry's on_change
      registry = Module.new do
        @callbacks = []

        module_function

        def on_change(&block)
          @callbacks << block
        end

        def trigger_change
          @callbacks.each(&:call)
        end

        def reset!
          @callbacks.clear
        end
      end
      stub_const('Legion::Extensions::Catalog::Registry', registry)

      expect(Legion::MCP).to receive(:reset!)
      Legion::MCP::Server.register_catalog_listener
      registry.trigger_change
    end
  end
end
