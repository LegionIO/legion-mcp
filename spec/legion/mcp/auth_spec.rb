# frozen_string_literal: true

require 'spec_helper'
require 'legion/mcp/auth'

RSpec.describe Legion::MCP::Auth do
  before { allow(Legion::Settings).to receive(:dig).and_return(nil) }

  describe '.authenticate' do
    it 'returns error for nil token' do
      result = described_class.authenticate(nil)
      expect(result[:authenticated]).to be false
      expect(result[:error]).to eq('missing_token')
    end

    it 'validates API key from allowed list' do
      allow(Legion::Settings).to receive(:dig).with(:mcp, :auth, :allowed_api_keys).and_return(['valid-key'])
      result = described_class.authenticate('valid-key')
      expect(result[:authenticated]).to be true
      expect(result[:identity][:user_id]).to eq('api_key')
    end

    it 'rejects invalid API key' do
      allow(Legion::Settings).to receive(:dig).with(:mcp, :auth, :allowed_api_keys).and_return(['valid-key'])
      result = described_class.authenticate('bad-key')
      expect(result[:authenticated]).to be false
      expect(result[:error]).to eq('invalid_api_key')
    end

    context 'with JWT-shaped token' do
      let(:jwt_token) { 'header.payload.signature' }

      it 'returns crypt_unavailable when Legion::Crypt::JWT is not defined' do
        hide_const('Legion::Crypt::JWT') if defined?(Legion::Crypt::JWT)
        result = described_class.authenticate(jwt_token)
        expect(result[:authenticated]).to be false
        expect(result[:error]).to eq('crypt_unavailable')
      end

      it 'returns error for invalid JWT when Crypt is available' do
        next unless defined?(Legion::Crypt::JWT)

        result = described_class.authenticate(jwt_token)
        expect(result[:authenticated]).to be false
        expect(result[:error]).to be_a(String)
      end
    end
  end

  describe '.verify_jwt' do
    let(:valid_claims) do
      { sub: 'test-user', risk_tier: 'medium', tenant_id: 'tenant-1', worker_id: 'worker-1' }
    end

    before do
      crypt_jwt = Module.new do
        def self.verify(_token, **_opts)
          raise 'should be stubbed'
        end

        def self.decode(_token)
          raise 'should be stubbed'
        end
      end
      crypt_jwt.const_set(:ExpiredTokenError, Class.new(StandardError))
      crypt_jwt.const_set(:InvalidTokenError, Class.new(StandardError))
      stub_const('Legion::Crypt::JWT', crypt_jwt)
    end

    context 'with a verification key configured' do
      before do
        allow(Legion::Settings).to receive(:dig).with(:mcp, :auth, :jwt_secret).and_return('test-secret')
        allow(Legion::Settings).to receive(:dig).with(:mcp, :auth, :jwt_algorithm).and_return(nil)
        allow(Legion::Settings).to receive(:dig).with(:mcp, :auth, :jwt_issuer).and_return(nil)
      end

      it 'accepts a valid signed token via Legion::Crypt::JWT.verify' do
        allow(Legion::Crypt::JWT).to receive(:verify).and_return(valid_claims)
        result = described_class.verify_jwt('valid.jwt.token')
        expect(result[:authenticated]).to be true
        expect(result[:identity][:user_id]).to eq('test-user')
        expect(result[:identity][:risk_tier]).to eq(:medium)
        expect(result[:identity][:tenant_id]).to eq('tenant-1')
      end

      it 'calls verify with the configured key and options' do
        allow(Legion::Crypt::JWT).to receive(:verify).and_return(valid_claims)
        described_class.verify_jwt('valid.jwt.token')
        expect(Legion::Crypt::JWT).to have_received(:verify).with(
          'valid.jwt.token',
          verification_key: 'test-secret',
          algorithm: 'HS256',
          issuer: 'legion',
          verify_expiration: true,
          verify_issuer: true
        )
      end

      it 'rejects a forged token when verify raises InvalidTokenError' do
        allow(Legion::Crypt::JWT).to receive(:verify)
          .and_raise(Legion::Crypt::JWT::InvalidTokenError, 'token signature verification failed')
        result = described_class.verify_jwt('forged.jwt.token')
        expect(result[:authenticated]).to be false
        expect(result[:error]).to include('signature verification failed')
      end

      it 'rejects an expired token when verify raises ExpiredTokenError' do
        allow(Legion::Crypt::JWT).to receive(:verify)
          .and_raise(Legion::Crypt::JWT::ExpiredTokenError, 'token has expired')
        result = described_class.verify_jwt('expired.jwt.token')
        expect(result[:authenticated]).to be false
        expect(result[:error]).to include('expired')
      end
    end

    context 'without a verification key (fallback decode)' do
      before do
        allow(Legion::Settings).to receive(:dig).with(:mcp, :auth, :jwt_secret).and_return(nil)
        allow(Legion::Settings).to receive(:dig).with(:mcp, :auth, :jwt_algorithm).and_return(nil)
        allow(Legion::Settings).to receive(:dig).with(:mcp, :auth, :jwt_issuer).and_return(nil)
      end

      it 'accepts a token with valid claims via decode fallback' do
        allow(Legion::Crypt::JWT).to receive(:decode)
          .and_return(valid_claims.merge(exp: Time.now.to_i + 3600))
        result = described_class.verify_jwt('unverified.jwt.token')
        expect(result[:authenticated]).to be true
        expect(result[:identity][:user_id]).to eq('test-user')
      end

      it 'rejects a token missing the sub claim' do
        allow(Legion::Crypt::JWT).to receive(:decode)
          .and_return({ exp: Time.now.to_i + 3600 })
        result = described_class.verify_jwt('no-sub.jwt.token')
        expect(result[:authenticated]).to be false
        expect(result[:error]).to include('sub')
      end

      it 'rejects a token that has expired' do
        allow(Legion::Crypt::JWT).to receive(:decode)
          .and_return(valid_claims.merge(exp: Time.now.to_i - 60))
        result = described_class.verify_jwt('expired.jwt.token')
        expect(result[:authenticated]).to be false
        expect(result[:error]).to include('expired')
      end
    end
  end

  describe '.auth_enabled?' do
    it 'returns false when not configured' do
      expect(described_class.auth_enabled?).to be false
    end

    it 'returns true when enabled in settings' do
      allow(Legion::Settings).to receive(:dig).with(:mcp, :auth, :enabled).and_return(true)
      expect(described_class.auth_enabled?).to be true
    end
  end

  describe '.require_auth?' do
    it 'returns false when not configured' do
      expect(described_class.require_auth?).to be false
    end

    it 'returns true when require_auth is set in settings' do
      allow(Legion::Settings).to receive(:dig).with(:mcp, :auth, :require_auth).and_return(true)
      expect(described_class.require_auth?).to be true
    end
  end

  describe '.default_identity' do
    it 'returns an anonymous low-risk identity' do
      identity = described_class.default_identity
      expect(identity[:user_id]).to eq('anonymous')
      expect(identity[:risk_tier]).to eq(:low)
    end
  end

  describe '.jwt_token?' do
    it 'identifies JWT tokens by dot count' do
      expect(described_class.jwt_token?('a.b.c')).to be true
      expect(described_class.jwt_token?('plain-key')).to be false
    end
  end
end
