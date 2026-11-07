# frozen_string_literal: true

require 'spec_helper'
require 'open3'
require 'rbconfig'
require 'tmpdir'

RSpec.describe 'MCP core-library settings boot' do
  def boot_mcp(config: nil)
    Dir.mktmpdir('legion-mcp-settings-') do |home|
      config_path = File.join(home, 'settings.json')
      File.write(config_path, Legion::JSON.dump(config)) if config
      environment = ENV.keys.grep(/\ALEGION_/).to_h { |key| [key, nil] }.merge(
        'HOME' => home, 'LEGION_DNS_BOOTSTRAP' => 'false', 'LEGION_SETTINGS_DIRS' => home, 'LEGION_MODE' => 'lite'
      )
      script = <<~RUBY
        require 'legion/logging'
        Legion::Logging.setup(level: 'error', async: false, log_file: File::NULL, log_stdout: false, rotation: false)
        unless ARGV.first.empty?
          require 'legion/settings'
          Legion::Settings.load(config_file: ARGV.first)
        end
        require 'legion/mcp'
        Legion::Settings.validate!

        server = Legion::MCP::Server.build(identity: { role: :reader, risk_tier: :low })
        request = Legion::JSON.dump({ jsonrpc: '2.0', id: 1, method: 'tools/list', params: {} })
        response = Legion::JSON.load(server.handle_json(request))
        probe = Class.new(MCP::Tool) { tool_name 'boot.deferred_probe'; input_schema(properties: {}) }
        Legion::Settings[:mcp][:roles][:reader] = false
        denied_request = Legion::JSON.dump({
          jsonrpc: '2.0', id: 2, method: 'tools/call', params: { name: 'legion.tools', arguments: {} }
        })
        denied = Legion::JSON.load(server.handle_json(denied_request))
        puts Legion::JSON.dump({
          tools: response.fetch(:result).fetch(:tools).map { |tool| tool.fetch(:name) },
          deferred: Legion::MCP::DeferredRegistry.deferred?(probe),
          configured_key: Legion::MCP::Auth.authenticate('configured-boot-key')[:authenticated],
          unknown_key: Legion::MCP::Auth.authenticate('unknown-boot-key')[:authenticated],
          self_generation: Legion::MCP::SelfGenerate.enabled?,
          revoked: denied.dig(:result, :isError)
        })
      RUBY
      stdout, stderr, status = Open3.capture3(
        environment, RbConfig.ruby, '-I', File.expand_path('../../../lib', __dir__), '-e', script,
        config ? config_path : '', chdir: home
      )
      expect(status.success?).to be(true), stderr
      Legion::JSON.load(stdout)
    end
  end

  it 'boots and validates the real framework settings tree without injecting a loader' do
    result = boot_mcp

    expect(result.fetch(:tools)).to include('legion.tools', 'legion.skill.describe')
    expect(result.fetch(:unknown_key)).to be false
    expect(result.fetch(:revoked)).to be true
  end

  it 'preserves loaded configuration through core payload merges and schema validation' do
    result = boot_mcp(config: {
                        mcp: {
                          auth: { enabled: true, allowed_api_keys: ['configured-boot-key'] },
                          governance: { enabled: false },
                          roles: { reader: { tools: ['legion.tools'] } },
                          deferred_loading: { enabled: false },
                          tier0: { guards: { rapid_fire_threshold: 2 } },
                          cold_start: { patterns_path: nil }
                        },
                        codegen: { self_generate: { enabled: true } }
                      })

    expect(result.fetch(:tools)).to eq(['legion.tools'])
    expect(result.fetch(:deferred)).to be false
    expect(result.fetch(:configured_key)).to be true
    expect(result.fetch(:unknown_key)).to be false
    expect(result.fetch(:self_generation)).to be true
    expect(result.fetch(:revoked)).to be true
  end
end
