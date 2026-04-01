# frozen_string_literal: true

require 'spec_helper'
require 'legion/mcp'
require 'tmpdir'

RSpec.describe Legion::MCP::Tools::SearchSessions do
  let(:tmpdir) { Dir.mktmpdir('legion-sessions') }

  let(:session_data) do
    {
      name:     'test-session',
      model:    'test-model',
      messages: [
        { role: 'user', content: 'How do I deploy to production?' },
        { role: 'assistant', content: 'You can deploy using the CI pipeline.' },
        { role: 'user', content: 'What about the staging environment?' }
      ]
    }
  end

  let(:other_session_data) do
    {
      name:     'other-session',
      model:    'test-model',
      messages: [
        { role: 'user', content: 'Check the database health.' },
        { role: 'assistant', content: 'Database is healthy.' }
      ]
    }
  end

  before do
    allow(Legion::Settings).to receive(:dig).and_return(nil)
    allow(Legion::Settings).to receive(:dig).with(:chat, :sessions_dir).and_return(tmpdir)

    File.write(File.join(tmpdir, 'session1.json'), Legion::JSON.dump(session_data))
    File.write(File.join(tmpdir, 'session2.json'), Legion::JSON.dump(other_session_data))
  end

  after do
    FileUtils.rm_rf(tmpdir)
  end

  describe '.call' do
    context 'with matching query' do
      it 'returns matching sessions' do
        response = described_class.call(query: 'deploy')
        expect(response.error?).to be false
        data = Legion::JSON.load(response.content.first[:text])
        expect(data[:results]).to be_an(Array)
        expect(data[:results].first[:session]).to eq('test-session')
      end

      it 'returns match count' do
        response = described_class.call(query: 'deploy')
        data = Legion::JSON.load(response.content.first[:text])
        expect(data[:results].first[:matches]).to be >= 1
      end

      it 'returns context snippet' do
        response = described_class.call(query: 'deploy')
        data = Legion::JSON.load(response.content.first[:text])
        expect(data[:results].first[:context]).to include('deploy')
      end
    end

    context 'with no matches' do
      it 'returns empty results' do
        response = described_class.call(query: 'nonexistent_query_xyz')
        data = Legion::JSON.load(response.content.first[:text])
        expect(data[:results]).to eq([])
        expect(data[:total]).to eq(0)
      end
    end

    context 'with empty query' do
      it 'returns error' do
        response = described_class.call(query: '')
        expect(response.error?).to be true
        data = Legion::JSON.load(response.content.first[:text])
        expect(data[:error]).to include('empty')
      end
    end

    context 'with limit parameter' do
      it 'respects the limit' do
        response = described_class.call(query: 'the', limit: 1)
        data = Legion::JSON.load(response.content.first[:text])
        expect(data[:results].size).to be <= 1
      end
    end

    context 'when sessions directory does not exist' do
      before do
        allow(Legion::Settings).to receive(:dig).with(:chat, :sessions_dir).and_return('/nonexistent/dir')
      end

      it 'returns empty results' do
        response = described_class.call(query: 'deploy')
        data = Legion::JSON.load(response.content.first[:text])
        expect(data[:results]).to eq([])
      end
    end

    context 'when results are sorted by relevance' do
      it 'puts sessions with more matches first' do
        response = described_class.call(query: 'the')
        data = Legion::JSON.load(response.content.first[:text])
        next unless data[:results].size > 1

        matches = data[:results].map { |r| r[:matches] }
        expect(matches).to eq(matches.sort.reverse)
      end
    end

    context 'when an error occurs' do
      before do
        allow(Dir).to receive(:exist?).and_return(true)
        allow(Dir).to receive(:glob).and_raise(StandardError, 'permission denied')
      end

      it 'returns error response' do
        response = described_class.call(query: 'test')
        expect(response.error?).to be true
        data = Legion::JSON.load(response.content.first[:text])
        expect(data[:error]).to include('permission denied')
      end
    end
  end
end
