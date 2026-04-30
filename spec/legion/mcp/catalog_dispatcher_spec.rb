# frozen_string_literal: true

require 'spec_helper'
require 'legion/mcp'

RSpec.describe Legion::MCP::CatalogDispatcher do
  let(:logger) { spy('logger') }

  before do
    allow(Legion::Settings).to receive(:dig).and_return(nil)
    allow(described_class).to receive(:log).and_return(logger)
    allow(Legion::MCP::LoggingSupport).to receive(:log).and_return(logger)
  end

  describe '.dispatch' do
    context 'when Ingress is defined' do
      it 'routes through Legion::Ingress.run' do
        expect(Legion::Ingress).to receive(:run).with(
          payload:       { url: 'https://example.com' },
          runner_class:  'Legion::Extensions::Http::Runners::Request',
          function:      :get,
          source:        :mcp,
          check_subtask: true,
          generate_task: true
        ).and_return({ status: 200 })

        result = described_class.dispatch(
          runner_class: 'Legion::Extensions::Http::Runners::Request',
          function:     'get',
          params:       { url: 'https://example.com' }
        )
        expect(result).to eq({ status: 200 })
      end

      it 'logs dispatch start and completion' do
        allow(Legion::Ingress).to receive(:run).and_return({ status: 200 })

        described_class.dispatch(
          runner_class: 'Legion::Extensions::Http::Runners::Request',
          function:     'get',
          params:       { url: 'https://example.com' }
        )

        expect(logger).to have_received(:info).with(include('[mcp] catalog.dispatch.start', 'function="get"'))
        expect(logger).to have_received(:info).with(include('[mcp] catalog.dispatch.complete', 'result='))
      end
    end

    context 'when Ingress is not defined' do
      before do
        hide_const('Legion::Ingress')
      end

      it 'returns nil' do
        result = described_class.dispatch(
          runner_class: 'SomeRunner',
          function:     'some_fn',
          params:       {}
        )
        expect(result).to be_nil
      end
    end
  end

  describe '.build_tool_class' do
    let(:entry) do
      {
        runner_class: 'Legion::Extensions::Http::Runners::Request',
        function:     'get',
        tool_name:    'legion.http.request.get',
        description:  'Execute an HTTP GET request',
        input_schema: { properties: { url: { type: 'string' } }, required: ['url'] },
        category:     'http',
        tier:         :low
      }
    end

    it 'returns a class that inherits from MCP::Tool' do
      klass = described_class.build_tool_class(entry)
      expect(klass.ancestors).to include(MCP::Tool)
    end

    it 'sets tool_name from entry' do
      klass = described_class.build_tool_class(entry)
      expect(klass.tool_name).to eq('legion.http.request.get')
    end

    it 'sets description from entry' do
      klass = described_class.build_tool_class(entry)
      expect(klass.description).to eq('Execute an HTTP GET request')
    end

    it 'sets mcp_category from entry' do
      klass = described_class.build_tool_class(entry)
      expect(klass.mcp_category).to eq('http')
    end

    it 'sets mcp_tier from entry' do
      klass = described_class.build_tool_class(entry)
      expect(klass.mcp_tier).to eq(:low)
    end

    it 'marks class as catalog_entry' do
      klass = described_class.build_tool_class(entry)
      expect(klass.catalog_entry).to be true
    end

    it 'dispatches call through CatalogDispatcher.dispatch' do
      klass = described_class.build_tool_class(entry)
      expect(described_class).to receive(:dispatch).with(
        runner_class: 'Legion::Extensions::Http::Runners::Request',
        function:     'get',
        params:       { url: 'https://example.com' }
      ).and_return({ status: 200 })

      response = klass.call(url: 'https://example.com')
      expect(response).to be_a(MCP::Tool::Response)
      expect(response.error?).to be false
    end

    it 'logs tool call start and completion' do
      klass = described_class.build_tool_class(entry)
      allow(described_class).to receive(:dispatch).and_return({ status: 200 })

      klass.call(url: 'https://example.com')

      expect(logger).to have_received(:info).with(include('[mcp] catalog.tool_call.start', 'tool_name="legion.http.request.get"'))
      expect(logger).to have_received(:info).with(include('[mcp] catalog.tool_call.complete', 'tool_name="legion.http.request.get"'))
    end

    it 'returns error when dispatch returns nil' do
      klass = described_class.build_tool_class(entry)
      allow(described_class).to receive(:dispatch).and_return(nil)

      response = klass.call(url: 'https://example.com')
      expect(response.error?).to be true
      data = Legion::JSON.load(response.content.first[:text])
      expect(data[:error]).to include('Ingress not available')
    end

    it 'returns error when dispatch raises' do
      klass = described_class.build_tool_class(entry)
      allow(described_class).to receive(:dispatch).and_raise(StandardError, 'timeout')

      response = klass.call(url: 'https://example.com')
      expect(response.error?).to be true
      data = Legion::JSON.load(response.content.first[:text])
      expect(data[:error]).to include('timeout')
    end
  end

  describe '.generate_tools_from_catalog' do
    context 'when Legion::Settings::Extensions is not defined' do
      before { hide_const('Legion::Settings::Extensions') }

      it 'returns empty array' do
        expect(described_class.generate_tools_from_catalog).to eq([])
      end
    end

    context 'when Legion::Settings::Extensions has no tools' do
      before do
        stub_const('Legion::Settings::Extensions', Module.new do
          module_function

          def tools
            []
          end
        end)
      end

      it 'returns empty array' do
        expect(described_class.generate_tools_from_catalog).to eq([])
      end
    end
  end
end
