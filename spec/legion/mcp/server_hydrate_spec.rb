# frozen_string_literal: true

require 'spec_helper'
require 'legion/mcp'

RSpec.describe 'MCP Server hydrates OverrideConfidence at boot' do
  before { allow(Legion::Settings).to receive(:dig).and_return(nil) }

  it 'calls hydrate methods during Server.build' do
    confidence_mod = Module.new do
      module_function

      def hydrate_from_l2; end

      def hydrate_from_apollo; end
    end
    stub_const('Legion::LLM::OverrideConfidence', confidence_mod)

    expect(confidence_mod).to receive(:hydrate_from_l2)
    expect(confidence_mod).to receive(:hydrate_from_apollo)

    Legion::MCP::Server.build
  end

  it 'does not crash when OverrideConfidence is not defined' do
    # OverrideConfidence is not stubbed, may or may not be defined
    # Server.build should not raise
    expect { Legion::MCP::Server.build }.not_to raise_error
  end
end
