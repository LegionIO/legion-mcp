# frozen_string_literal: true

require 'spec_helper'
require 'legion/mcp'

RSpec.describe 'MCP skill tools' do
  let(:skill_class) do
    double(:skill_class,
           skill_name:    'brainstorming',
           namespace:     'superpowers',
           description:   'Collaborative design',
           trigger_words: ['brainstorm'],
           trigger:       :on_demand,
           follows_skill: nil,
           steps:         [:ideate])
  end

  before do
    stub_const('Legion::LLM::Skills::Registry', Module.new do
      def self.all; []; end

      def self.find(_key); nil; end
    end)
  end

  def parse_response(response)
    Legion::JSON.load(response.content.first[:text])
  end

  describe Legion::MCP::Tools::SkillList do
    it 'returns empty skills list when registry is empty' do
      response = described_class.call
      expect(response).to be_a(MCP::Tool::Response)
      expect(response.error?).to be false
      data = parse_response(response)
      expect(data[:skills]).to eq([])
    end

    it 'returns skills when registry has entries' do
      sc = skill_class
      allow(Legion::LLM::Skills::Registry).to receive(:all).and_return([sc])
      response = described_class.call
      expect(response).to be_a(MCP::Tool::Response)
      data = parse_response(response)
      expect(data[:skills].first[:name]).to eq('brainstorming')
    end
  end

  describe Legion::MCP::Tools::SkillDescribe do
    it 'returns error for unknown skill' do
      response = described_class.call(name: 'unknown')
      expect(response).to be_a(MCP::Tool::Response)
      data = parse_response(response)
      expect(data[:error]).to match(/not found/)
    end

    it 'returns metadata for a known skill' do
      sc = skill_class
      allow(Legion::LLM::Skills::Registry).to receive(:find).with('superpowers:brainstorming').and_return(sc)
      response = described_class.call(name: 'superpowers:brainstorming')
      expect(response).to be_a(MCP::Tool::Response)
      data = parse_response(response)
      expect(data[:name]).to eq('brainstorming')
    end
  end

  describe Legion::MCP::Tools::SkillInvoke do
    it 'returns error when Skills not available' do
      hide_const('Legion::LLM::Skills::Registry')
      response = described_class.call(name: 'superpowers:brainstorming', conversation_id: 'conv_abc')
      expect(response).to be_a(MCP::Tool::Response)
      data = parse_response(response)
      expect(data[:error]).to be_a(String)
    end

    it 'returns error when skill not found' do
      response = described_class.call(name: 'unknown:skill', conversation_id: 'conv_abc')
      expect(response).to be_a(MCP::Tool::Response)
      data = parse_response(response)
      expect(data[:error]).to match(/not found/)
    end
  end

  describe Legion::MCP::Tools::SkillCancel do
    it 'returns cancelled true when skill was active' do
      stub_const('Legion::LLM::ConversationStore', Module.new do
        def self.cancel_skill!(_id); { skill_key: 'superpowers:brainstorming' }; end
      end)
      response = described_class.call(conversation_id: 'conv_abc')
      expect(response).to be_a(MCP::Tool::Response)
      data = parse_response(response)
      expect(data[:cancelled]).to be(true)
    end

    it 'returns not_running when no active skill' do
      stub_const('Legion::LLM::ConversationStore', Module.new do
        def self.cancel_skill!(_id); nil; end
      end)
      response = described_class.call(conversation_id: 'conv_abc')
      expect(response).to be_a(MCP::Tool::Response)
      data = parse_response(response)
      expect(data[:cancelled]).to be(false)
      expect(data[:reason]).to eq('not_running')
    end
  end
end
