# frozen_string_literal: true

require 'concurrent'
require 'mcp'
require 'legion/json'
require 'legion/logging'
require_relative 'mcp/version'

require_relative 'mcp/settings'
require_relative 'mcp/auth'
require_relative 'mcp/tool_governance'
require_relative 'mcp/server'
require_relative 'mcp/override_broadcast'
require_relative 'mcp/client'
require_relative 'mcp/actors/self_generate_cycle' if defined?(Legion::Extensions::Actors::Every)

module Legion
  module MCP
    class << self
      include Legion::Logging::Helper

      def server
        log.debug 'Building Legion::MCP server' unless @server
        @server ||= Server.build
      rescue StandardError => e
        handle_exception(e, level: :error, operation: 'mcp.server')
        raise
      end

      def server_for(token:)
        log.debug { "Authenticating MCP server request token_present=#{!token.to_s.empty?}" }
        auth_result = Auth.authenticate(token)
        return { error: auth_result[:error] } unless auth_result[:authenticated]

        log.info { "Building identity-scoped MCP server identity=#{auth_result[:identity]}" }
        Server.build(identity: auth_result[:identity])
      rescue StandardError => e
        handle_exception(e, level: :error, operation: 'mcp.server_for', token_present: !token.to_s.empty?)
        { error: e.message }
      end

      def reset!
        log.info 'Resetting Legion::MCP server cache' if @server
        @server = nil
      end
    end
  end
end
