# frozen_string_literal: true

require 'spec_helper'
require 'legion/mcp'

# Stub Capability and Catalog::Registry for tests
unless defined?(Legion::Extensions::Capability)
  module Legion
    module Extensions
      Capability = ::Data.define(
        :name, :extension, :runner, :function,
        :description, :parameters, :tags, :loaded_at
      ) do
        def self.from_runner(extension:, runner:, function:, description: nil, parameters: nil, tags: nil)
          canonical = "#{extension}:#{runner.to_s.gsub(/([A-Z])/, '_\1').sub(/^_/, '').downcase}:#{function}"
          new(
            name: canonical, extension: extension, runner: runner.to_s,
            function: function.to_s, description: description,
            parameters: parameters || {}, tags: Array(tags), loaded_at: Time.now
          )
        end

        def to_mcp_tool
          snake_runner = runner.gsub(/([A-Z])/, '_\1').sub(/^_/, '').downcase
          {
            name: "legion.#{extension.delete_prefix('lex-').tr('-', '_')}.#{snake_runner}.#{function}",
            description: description || "#{extension} #{runner}##{function}",
            input_schema: { type: 'object', properties: {}, required: [] }
          }
        end
      end

      module Catalog
        module Registry
          @capabilities = []
          @by_name = {}
          @mutex = Mutex.new

          module_function

          def register(capability)
            @mutex.synchronize do
              return if @by_name.key?(capability.name)

              @capabilities << capability
              @by_name[capability.name] = capability
            end
          end

          def for_mcp
            @mutex.synchronize { @capabilities.dup }
          end

          def find_by_mcp_name(mcp_name)
            @mutex.synchronize do
              @capabilities.find do |cap|
                cap.to_mcp_tool[:name] == mcp_name
              end
            end
          end

          def reset!
            @mutex.synchronize do
              @capabilities.clear
              @by_name.clear
            end
          end
        end
      end
    end
  end
end

RSpec.describe 'MCP Server dynamic dispatch' do
  before do
    allow(Legion::Settings).to receive(:dig).and_return(nil)
    Legion::Extensions::Catalog::Registry.reset!
  end

  describe '.dispatch_catalog_tool' do
    it 'dispatches to extension runner when tool is from Catalog' do
      cap = Legion::Extensions::Capability.from_runner(
        extension: 'lex-github', runner: 'PullRequest', function: 'close',
        description: 'Close a PR'
      )
      Legion::Extensions::Catalog::Registry.register(cap)

      runner = double('PullRequest')
      allow(runner).to receive(:close).with(pr_id: 123).and_return({ closed: true })
      stub_const('Legion::Extensions::Github::Runners::PullRequest', runner)

      result = Legion::MCP::Server.dispatch_catalog_tool(
        'legion.github.pull_request.close',
        { pr_id: 123 }
      )
      expect(result[:status]).to eq(:success)
      expect(result[:result]).to eq({ closed: true })
    end

    it 'returns nil for unknown tool names' do
      result = Legion::MCP::Server.dispatch_catalog_tool('unknown.tool', {})
      expect(result).to be_nil
    end
  end
end
