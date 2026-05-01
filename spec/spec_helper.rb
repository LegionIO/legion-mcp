# frozen_string_literal: true

require 'simplecov'
SimpleCov.start do
  add_filter '/spec/'
  enable_coverage :branch
end

unless defined?(Legion::Logging)
  module Legion
    module Logging
      module Helper
        def log
          Legion::Logging
        end

        def handle_exception(_error, **_opts)
          nil
        end
      end

      class << self
        def debug(_msg = nil); end
        def info(_msg = nil); end
        def warn(_msg = nil); end
        def error(_msg = nil); end
      end
    end
  end
end
require 'legion/logging'
require 'legion/settings'
require 'legion/mcp'
Legion::Settings[:logging][:level] = :error
Legion::Logging.setup(level: :error, extended: false, log_stdout: false, trace_size: 0)
RSpec.configure do |config|
  config.expect_with :rspec do |expectations|
    expectations.include_chain_clauses_in_custom_matcher_descriptions = true
  end

  config.mock_with :rspec do |mocks|
    mocks.verify_partial_doubles = false
  end

  config.shared_context_metadata_behavior = :apply_to_host_groups
  config.order = :random
  Kernel.srand config.seed
end

# Stub LegionIO framework classes that tools reference
# These are guarded with defined?() in production code
unless defined?(Legion::VERSION)
  module Legion
    VERSION = '0.0.0-test'
  end
end

unless defined?(Legion::Ingress)
  module Legion
    module Ingress
      def self.run(**_args); end
    end
  end
end
