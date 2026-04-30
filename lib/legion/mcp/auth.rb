# frozen_string_literal: true

module Legion
  module MCP
    module Auth # rubocop:disable Metrics/ModuleLength
      extend Legion::Logging::Helper

      module_function

      def authenticate(token)
        log.info('Starting legion.mcp.auth.authenticate')
        return { authenticated: false, error: 'missing_token' } unless token

        if jwt_token?(token)
          verify_jwt(token)
        else
          verify_api_key(token)
        end
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

      def verify_jwt(token) # rubocop:disable Metrics/MethodLength
        return { authenticated: false, error: 'crypt_unavailable' } unless defined?(Legion::Crypt::JWT)

        verification_key = jwt_verification_key
        claims = if verification_key
                   Legion::Crypt::JWT.verify(
                     token,
                     verification_key: verification_key,
                     algorithm: jwt_algorithm,
                     issuer: jwt_issuer,
                     verify_expiration: true,
                     verify_issuer: true
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
        if allowed.include?(token)
          { authenticated: true, identity: { user_id: 'api_key', risk_tier: :low } }
        else
          { authenticated: false, error: 'invalid_api_key' }
        end
      end

      def jwt_verification_key
        configured = Legion::Settings.dig(:mcp, :auth, :jwt_secret)
        return configured if configured

        if defined?(Legion::Crypt::ClusterSecret) && Legion::Crypt::ClusterSecret.respond_to?(:cs)
          return Legion::Crypt::ClusterSecret.cs
        end

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
        { user_id: claims[:sub], risk_tier: claims[:risk_tier]&.to_sym,
          tenant_id: claims[:tenant_id], worker_id: claims[:worker_id] }
      end
    end
  end
end
