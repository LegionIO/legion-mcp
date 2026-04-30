# frozen_string_literal: true

require 'spec_helper'
require 'legion/mcp/server'

RSpec.describe Legion::MCP::Resources::RunnerCatalog do
  describe '#catalog_json (private)' do
    context 'when Settings::Extensions.runners is available and populated' do
      let(:mock_extensions) do
        Module.new do
          def self.runners
            [
              { name: 'ollama/inference/chat', extension: 'lex-ollama', function: 'chat', exposed: true },
              { name: 'http/request/get', extension: 'lex-http', function: 'get', exposed: true }
            ]
          end
        end
      end

      before { stub_const('Legion::Settings::Extensions', mock_extensions) }

      it 'returns runner entries from the centralized registry' do
        result = described_class.send(:catalog_json)
        parsed = Legion::JSON.load(result)
        expect(parsed).to be_an(Array)
        expect(parsed.size).to eq(2)
        expect(parsed.first[:name]).to eq('ollama/inference/chat')
        expect(parsed.first[:extension]).to eq('lex-ollama')
      end

      it 'does not query legion-data models' do
        # If data models were called, they would raise since they are not defined
        expect { described_class.send(:catalog_json) }.not_to raise_error
      end
    end

    context 'when Settings::Extensions has no runners registered' do
      before do
        allow(described_class).to receive(:data_connected?).and_return(false)
      end

      it 'returns an error when data is not connected' do
        result = described_class.send(:catalog_json)
        parsed = Legion::JSON.load(result)
        expect(parsed[:error]).to include('not connected')
      end
    end

    context 'when Settings::Extensions.runners is empty' do
      let(:empty_extensions) do
        Module.new do
          def self.runners
            []
          end
        end
      end

      before do
        stub_const('Legion::Settings::Extensions', empty_extensions)
        allow(described_class).to receive(:data_connected?).and_return(false)
      end

      it 'falls back to data query path' do
        result = described_class.send(:catalog_json)
        parsed = Legion::JSON.load(result)
        expect(parsed[:error]).to include('not connected')
      end
    end
  end

  describe '#settings_extensions_runners_available? (private)' do
    it 'returns falsy when the Settings::Extensions registry has no runners' do
      expect(described_class.send(:settings_extensions_runners_available?)).to be_falsey
    end

    it 'returns true when runners are populated' do
      mock_ext = Module.new do
        def self.runners
          [{ name: 'test/runner' }]
        end
      end
      stub_const('Legion::Settings::Extensions', mock_ext)
      expect(described_class.send(:settings_extensions_runners_available?)).to be true
    end

    it 'returns false when runners are empty' do
      mock_ext = Module.new do
        def self.runners
          []
        end
      end
      stub_const('Legion::Settings::Extensions', mock_ext)
      expect(described_class.send(:settings_extensions_runners_available?)).to be false
    end
  end
end
