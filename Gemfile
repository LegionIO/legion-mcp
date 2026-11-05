# frozen_string_literal: true

source 'https://rubygems.org'
gemspec

companion_root = File.directory?(File.expand_path('.ci-dependencies', __dir__)) ? '.ci-dependencies' : '..'
settings_path = File.expand_path("#{companion_root}/legion-settings", __dir__)
gem 'legion-settings', path: settings_path if File.directory?(settings_path)

gem 'rake'
gem 'rspec'
gem 'rubocop'
gem 'rubocop-legion'
gem 'rubocop-rspec'
gem 'simplecov'
