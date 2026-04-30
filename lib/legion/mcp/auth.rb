# frozen_string_literal: true

module Legion
  module MCP
    module Auth
      extend Legion::Logging::Helper

      module_function

      def authenticate(token)
        token_type = token ? (jwt_token?(token) ? :jwt : :api_key) : :none
        log.debug("[mcp][auth] action=authenticate token_type=#{token_type}")
        return { authenticated: false, error: 'missing_token' } unless token

        result = if jwt_token?(token)
                   verify_jwt(token)
                 else
                   verify_api_key(token)
                 end
        log.debug("[mcp][auth] action=authenticate.complete authenticated=#{result[:authenticated]}")
        result
      end

      def auth_enabled?
        Legion::Settings.dig(:mcp, :auth, :enabled) == true
      end

      def require_auth?
        Legion::Settings.dig(:mcp, :auth, :require_auth) == true
      end

      def default_identity
        { user_id: 'anonymous', risk_tier: :low }
      end

      def jwt_token?(token)
        token.count('.') == 2
      end

      def verify_jwt(token)
        log.debug("[mcp][auth] action=verify_jwt crypt_available=#{defined?(Legion::Crypt::JWT) ? true : false}")
        return { authenticated: false, error: 'crypt_unavailable' } unless defined?(Legion::Crypt::JWT)

        verification_key = jwt_verification_key
        claims = if verification_key
                   Legion::Crypt::JWT.verify(
                     token,
                     verification_key:  verification_key,
                     algorithm:         jwt_algorithm,
                     issuer:            jwt_issuer,
                     verify_expiration: true,
                     verify_issuer:     true
                   )
                 else
                   log.warn('No JWT verification key available; falling back to unverified decode')
                   decoded = Legion::Crypt::JWT.decode(token)
                   validate_claims!(decoded)
                   decoded
                 end

        { authenticated: true, identity: identity_from_claims(claims) }
      rescue StandardError => e
        handle_exception(e, level: :warn, operation: 'legion.mcp.auth.verify_jwt')
        log.warn("Auth#verify_jwt failed: #{e.message}")
        { authenticated: false, error: e.message }
      end

      def verify_api_key(token)
        allowed = Legion::Settings.dig(:mcp, :auth, :allowed_api_keys) || []
        matched = allowed.include?(token)
        log.debug("[mcp][auth] action=verify_api_key allowed_keys=#{allowed.size} matched=#{matched}")
        if matched
          { authenticated: true, identity: { user_id: 'api_key', risk_tier: :low } }
        else
          { authenticated: false, error: 'invalid_api_key' }
        end
      end

      def jwt_verification_key
        configured = Legion::Settings.dig(:mcp, :auth, :jwt_secret)
        return configured if configured

        return Legion::Crypt::ClusterSecret.cs if defined?(Legion::Crypt::ClusterSecret) && Legion::Crypt::ClusterSecret.respond_to?(:cs)

        nil
      end

      def jwt_algorithm
        Legion::Settings.dig(:mcp, :auth, :jwt_algorithm) || 'HS256'
      end

      def jwt_issuer
        Legion::Settings.dig(:mcp, :auth, :jwt_issuer) || 'legion'
      end

      def validate_claims!(claims)
        raise 'token missing required sub claim' unless claims[:sub]

        return unless claims[:exp]

        raise 'token has expired' if claims[:exp].to_i <= Time.now.to_i
      end

      def identity_from_claims(claims)
        identity = { user_id: claims[:sub], risk_tier: claims[:risk_tier]&.to_sym,
                     tenant_id: claims[:tenant_id], worker_id: claims[:worker_id] }
        log.debug("[mcp][auth] action=identity_from_claims user_id=#{identity[:user_id]} risk_tier=#{identity[:risk_tier]}")
        identity
      end
    end
  end
end
