# frozen_string_literal: true

require 'spec_helper'
require 'legion/mcp'

RSpec.describe Legion::MCP::Tools::GetConfig do
  let(:mock_loader) { double('loader', to_hash: { transport: { host: 'localhost' }, data: { password: 'secret' } }) }

  before { allow(Legion::Settings).to receive(:loader).and_return(mock_loader) }

  describe '.call' do
    it 'returns redacted config' do
      response = described_class.call
      expect(response).to be_a(MCP::Tool::Response)
      expect(response.error?).to be false
    end

    it 'returns error for unknown section' do
      response = described_class.call(section: 'nonexistent_section_xyz')
      expect(response.error?).to be true
      expect(response.content.first[:text]).to include('not found')
    end
  end
end
