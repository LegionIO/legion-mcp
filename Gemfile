# frozen_string_literal: true

source 'https://rubygems.org'
gemspec

unless ENV['CI']
  gem 'legion-cache', path: '../legion-cache'
  gem 'legion-data', path: '../legion-data'
  gem 'legionio', path: '../LegionIO'
  gem 'legion-json', path: '../legion-json'
  gem 'legion-llm', path: '../legion-llm'
  gem 'legion-logging', path: '../legion-logging'
  gem 'legion-settings', path: '../legion-settings'
end

gem 'rake'
gem 'rspec'
gem 'rubocop'
gem 'rubocop-rspec'
gem 'simplecov'
