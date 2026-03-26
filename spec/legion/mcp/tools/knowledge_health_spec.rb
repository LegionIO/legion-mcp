# frozen_string_literal: true

require 'spec_helper'
require 'legion/mcp'

RSpec.describe Legion::MCP::Tools::KnowledgeHealth do
  describe '.tool_name' do
    it 'is legion.knowledge_health' do
      expect(described_class.tool_name).to eq('legion.knowledge_health')
    end
  end

  describe '.call' do
    context 'when lex-knowledge is not available' do
      before do
        allow(described_class).to receive(:knowledge_available?).and_return(false)
      end

      it 'returns an error response' do
        response = described_class.call
        expect(response).to be_a(MCP::Tool::Response)
        expect(response.error?).to be true
      end

      it 'error message mentions lex-knowledge' do
        response = described_class.call
        data = Legion::JSON.load(response.content.first[:text])
        expect(data[:error]).to include('lex-knowledge')
      end
    end

    context 'when no corpus path is configured' do
      before do
        allow(described_class).to receive(:knowledge_available?).and_return(true)
        allow(described_class).to receive(:resolve_path).and_return(nil)
      end

      it 'returns an error response' do
        response = described_class.call
        expect(response).to be_a(MCP::Tool::Response)
        expect(response.error?).to be true
      end

      it 'error message mentions corpus path' do
        response = described_class.call
        data = Legion::JSON.load(response.content.first[:text])
        expect(data[:error]).to include('corpus path')
      end
    end

    context 'when lex-knowledge is available' do
      let(:health_result) { { success: true, local: { total: 10 }, apollo: {}, sync: {} } }

      before do
        allow(described_class).to receive(:knowledge_available?).and_return(true)
        stub_const('Legion::Extensions::Knowledge::Runners::Maintenance', Class.new)
        allow(Legion::Extensions::Knowledge::Runners::Maintenance).to receive(:health).and_return(health_result)
      end

      it 'returns a successful MCP::Tool::Response when path is provided' do
        response = described_class.call(path: '/some/path')
        expect(response).to be_a(MCP::Tool::Response)
        expect(response.error?).to be false
      end

      it 'passes path through to Runners::Maintenance.health' do
        expect(Legion::Extensions::Knowledge::Runners::Maintenance).to receive(:health).with(
          path: '/some/path'
        ).and_return(health_result)
        described_class.call(path: '/some/path')
      end

      it 'response content contains JSON text with result data' do
        response = described_class.call(path: '/some/path')
        data = Legion::JSON.load(response.content.first[:text])
        expect(data[:success]).to be true
      end

      it 'returns error response when Runners::Maintenance.health raises StandardError' do
        allow(Legion::Extensions::Knowledge::Runners::Maintenance).to receive(:health).and_raise(StandardError, 'health check failed')
        response = described_class.call(path: '/some/path')
        expect(response).to be_a(MCP::Tool::Response)
        expect(response.error?).to be true
        data = Legion::JSON.load(response.content.first[:text])
        expect(data[:error]).to include('health check failed')
      end
    end

    context 'when path is not provided and Legion::Settings is available' do
      let(:health_result) { { success: true, local: {}, apollo: {}, sync: {} } }

      before do
        allow(described_class).to receive(:knowledge_available?).and_return(true)
        stub_const('Legion::Extensions::Knowledge::Runners::Maintenance', Class.new)
        allow(Legion::Extensions::Knowledge::Runners::Maintenance).to receive(:health).and_return(health_result)
        allow(Legion::Settings).to receive(:dig).with(:knowledge, :corpus_path).and_return('/settings/path')
      end

      it 'falls back to settings corpus_path' do
        expect(Legion::Extensions::Knowledge::Runners::Maintenance).to receive(:health).with(
          path: '/settings/path'
        ).and_return(health_result)
        described_class.call
      end
    end
  end
end
