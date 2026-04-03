# frozen_string_literal: true

require_relative 'lib/legion/mcp/version'

Gem::Specification.new do |spec|
  spec.name = 'legion-mcp'
  spec.version       = Legion::MCP::VERSION
  spec.authors       = ['Esity']
  spec.email         = ['matthewdiverson@gmail.com']

  spec.summary       = 'MCP server for the LegionIO framework'
  spec.description   = 'Model Context Protocol server with semantic tool matching, observation pipeline, and tiered inference for LegionIO'
  spec.homepage      = 'https://github.com/LegionIO/legion-mcp'
  spec.license       = 'Apache-2.0'
  spec.required_ruby_version = '>= 3.4'
  spec.require_paths = ['lib']
  spec.files = `git ls-files -z`.split("\x0").reject { |f| f.match(%r{^(test|spec|features)/}) }
  spec.extra_rdoc_files = %w[README.md LICENSE CHANGELOG.md]
  spec.metadata = {
    'bug_tracker_uri'       => 'https://github.com/LegionIO/legion-mcp/issues',
    'changelog_uri'         => 'https://github.com/LegionIO/legion-mcp/blob/main/CHANGELOG.md',
    'documentation_uri'     => 'https://github.com/LegionIO/legion-mcp',
    'homepage_uri'          => 'https://github.com/LegionIO/LegionIO',
    'source_code_uri'       => 'https://github.com/LegionIO/legion-mcp',
    'wiki_uri'              => 'https://github.com/LegionIO/legion-mcp/wiki',
    'rubygems_mfa_required' => 'true'
  }

  spec.add_dependency 'concurrent-ruby', '>= 1.2'
  spec.add_dependency 'legion-data', '>= 1.4.19'
  spec.add_dependency 'legion-json', '>= 1.2.0'
  spec.add_dependency 'legion-logging', '>= 1.4.3'
  spec.add_dependency 'legion-settings', '>= 1.3.12'
  spec.add_dependency 'mcp', '~> 0.8'
end
