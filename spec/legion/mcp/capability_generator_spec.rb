# frozen_string_literal: true

require 'spec_helper'
require 'legion/mcp/capability_generator'

RSpec.describe Legion::MCP::CapabilityGenerator do
  let(:frequent_gap) do
    { type: :frequent_intent, tool: 'http.request.get', count: 10,
      sample_intents: ['check health', 'check status', 'get health'] }
  end

  let(:chain_gap) do
    { type: :repeated_chain, chain: %w[http.request.get consul.kv.put], count: 5 }
  end

  describe '.generate_from_gap' do
    it 'returns a generation proposal for frequent intents' do
      proposal = described_class.generate_from_gap(frequent_gap)
      expect(proposal).to include(:name, :description, :runner_code, :spec_code, :confidence)
      expect(proposal[:confidence]).to eq(:sandbox)
    end

    it 'returns a generation proposal for repeated chains' do
      proposal = described_class.generate_from_gap(chain_gap)
      expect(proposal[:name]).to include('then')
    end

    it 'returns nil runner_code when LLM unavailable' do
      proposal = described_class.generate_from_gap(frequent_gap)
      expect(proposal[:runner_code]).to be_nil
    end

    it 'generates code when LLM is available' do
      llm_mod = Module.new do
        def self.started?; true; end
        def self.ask(_prompt, **_opts); 'module Foo; end'; end
      end
      stub_const('Legion::LLM', llm_mod)

      proposal = described_class.generate_from_gap(frequent_gap)
      expect(proposal[:runner_code]).to eq('module Foo; end')
      expect(proposal[:spec_code]).to eq('module Foo; end')
    end
  end

  describe '.infer_name' do
    it 'generates name from frequent intent' do
      name = described_class.infer_name(frequent_gap)
      expect(name).to eq('check_health')
    end

    it 'generates name from repeated chain' do
      name = described_class.infer_name(chain_gap)
      expect(name).to include('then')
    end
  end

  describe '.validate' do
    it 'checks Ruby syntax validity' do
      result = described_class.validate(runner_code: 'def foo; 42; end', spec_code: nil)
      expect(result[:syntax_valid]).to be true
    end

    it 'rejects invalid Ruby syntax' do
      result = described_class.validate(runner_code: 'def foo; {; end', spec_code: nil)
      expect(result[:syntax_valid]).to be false
    end

    it 'returns false syntax_valid when runner_code is nil' do
      result = described_class.validate(runner_code: nil, spec_code: nil)
      expect(result[:syntax_valid]).to be false
    end
  end
end
