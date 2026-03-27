# frozen_string_literal: true

require 'spec_helper'
require 'legion/mcp'

RSpec.describe Legion::MCP::Tools::Absorb do
  describe '.tool_name' do
    it 'returns legion.absorb' do
      expect(described_class.tool_name).to eq('legion.absorb')
    end
  end

  describe '.call' do
    context 'when dispatch is not available' do
      before do
        allow(described_class).to receive(:dispatch_available?).and_return(false)
      end

      it 'returns an error response' do
        result = described_class.call(input: 'https://example.com/test')
        expect(result).to be_a(MCP::Tool::Response)
        expect(result.error?).to be true
      end

      it 'error message mentions not available' do
        result = described_class.call(input: 'https://example.com/test')
        data = Legion::JSON.load(result.content.first[:text])
        expect(data[:error]).to include('not available')
      end
    end

    context 'when dispatch is available' do
      before do
        allow(described_class).to receive(:dispatch_available?).and_return(true)
        stub_const('Legion::Extensions::Actors::AbsorberDispatch', Class.new)
      end

      it 'dispatches to AbsorberDispatch on success' do
        allow(Legion::Extensions::Actors::AbsorberDispatch).to receive(:dispatch).and_return(
          { success: true, job_id: 'test-1', absorber: 'TestAbsorber', result: {} }
        )
        result = described_class.call(input: 'https://example.com/test')
        expect(result).to be_a(MCP::Tool::Response)
        expect(result.error?).to be false
        data = Legion::JSON.load(result.content.first[:text])
        expect(data[:success]).to be true
        expect(data[:job_id]).to eq('test-1')
      end

      it 'passes scope as symbol in context' do
        expect(Legion::Extensions::Actors::AbsorberDispatch).to receive(:dispatch).with(
          input:   'https://example.com/test',
          context: { scope: :local }
        ).and_return({ success: true, job_id: 'j1', absorber: 'A', result: {} })
        described_class.call(input: 'https://example.com/test', scope: 'local')
      end

      it 'defaults scope to global' do
        expect(Legion::Extensions::Actors::AbsorberDispatch).to receive(:dispatch).with(
          input:   'https://example.com/test',
          context: { scope: :global }
        ).and_return({ success: true, job_id: 'j2', absorber: 'A', result: {} })
        described_class.call(input: 'https://example.com/test')
      end

      it 'returns error on dispatch failure' do
        allow(Legion::Extensions::Actors::AbsorberDispatch).to receive(:dispatch).and_return(
          { success: false, error: 'no handler found' }
        )
        result = described_class.call(input: 'https://unknown.com/page')
        expect(result).to be_a(MCP::Tool::Response)
        expect(result.error?).to be true
        data = Legion::JSON.load(result.content.first[:text])
        expect(data[:error]).to include('no handler found')
      end

      it 'returns error with generic message when dispatch failure has no error key' do
        allow(Legion::Extensions::Actors::AbsorberDispatch).to receive(:dispatch).and_return(
          { success: false }
        )
        result = described_class.call(input: 'https://unknown.com/page')
        expect(result.error?).to be true
        data = Legion::JSON.load(result.content.first[:text])
        expect(data[:error]).to include('absorption failed')
      end

      it 'returns error for invalid scope' do
        result = described_class.call(input: 'https://example.com/test', scope: 'invalid')
        expect(result).to be_a(MCP::Tool::Response)
        expect(result.error?).to be true
        data = Legion::JSON.load(result.content.first[:text])
        expect(data[:error]).to include('invalid scope')
      end

      it 'rescues StandardError and returns error response' do
        allow(Legion::Extensions::Actors::AbsorberDispatch).to receive(:dispatch).and_raise(
          StandardError, 'unexpected boom'
        )
        result = described_class.call(input: 'https://example.com/test')
        expect(result).to be_a(MCP::Tool::Response)
        expect(result.error?).to be true
        data = Legion::JSON.load(result.content.first[:text])
        expect(data[:error]).to include('unexpected boom')
      end
    end
  end

  describe '.dispatch_available?' do
    it 'returns false when AbsorberDispatch is not defined' do
      hide_const('Legion::Extensions::Actors::AbsorberDispatch') if defined?(Legion::Extensions::Actors::AbsorberDispatch)
      expect(described_class.send(:dispatch_available?)).to be_falsy
    end
  end
end
