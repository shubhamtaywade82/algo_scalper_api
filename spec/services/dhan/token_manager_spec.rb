# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Dhan::TokenManager do
  before do
    described_class.instance_variable_set(:@cached_token, nil)
    described_class.instance_variable_set(:@creds, nil)
    described_class.instance_variable_set(:@totp_refresh_cooldown_until, nil)
  end

  describe '.current_token!' do
    context 'when no token exists' do
      it 'generates and persists a token' do
        allow(ENV).to receive(:[]).and_call_original
        allow(ENV).to receive(:[]).with('DHAN_CLIENT_ID').and_return(nil)
        allow(ENV).to receive(:[]).with('CLIENT_ID').and_return('1000000001')
        allow(ENV).to receive(:[]).with('DHAN_PIN').and_return('123456')
        allow(ENV).to receive(:[]).with('DHAN_TOTP_SECRET').and_return('BASE32SECRET')

        allow(DhanHQ::Auth).to receive(:generate_totp).with('BASE32SECRET').and_return('123456')
        allow(DhanHQ::Auth).to receive(:generate_access_token).and_return(
          {
            'accessToken' => 'new_access_token',
            'expiryTime' => 2.hours.from_now.iso8601
          }
        )

        token = described_class.current_token!

        expect(token).to eq('new_access_token')
        record = DhanAccessToken.first
        expect(record).not_to be_nil
        expect(record.token).to eq('new_access_token')
      end
    end

    context 'when API returns error status' do
      it 'returns nil when no ENV token and logs the message' do
        allow(ENV).to receive(:[]).and_call_original
        allow(ENV).to receive(:[]).with('DHAN_CLIENT_ID').and_return('1000000001')
        allow(ENV).to receive(:[]).with('CLIENT_ID').and_return(nil)
        allow(ENV).to receive(:[]).with('DHAN_PIN').and_return('123456')
        allow(ENV).to receive(:[]).with('DHAN_TOTP_SECRET').and_return('BASE32SECRET')
        allow(ENV).to receive(:[]).with('DHAN_ACCESS_TOKEN').and_return(nil)
        allow(ENV).to receive(:[]).with('ACCESS_TOKEN').and_return(nil)
        allow(DhanHQ::Auth).to receive(:generate_totp).with('BASE32SECRET').and_return('123456')
        allow(DhanHQ::Auth).to receive(:generate_access_token).and_return(
          { 'status' => 'error', 'message' => 'Too many attempts. Please try again after sometime.' }
        )

        token = described_class.refresh!(force: true)

        expect(token).to be_nil
        expect(described_class.send(:totp_cooldown_active?)).to be true
      end

      context 'with memory cache store' do
        around do |example|
          original_cache = Rails.cache
          Rails.cache = ActiveSupport::Cache::MemoryStore.new
          example.run
        ensure
          Rails.cache = original_cache
        end

        it 'restores cooldown from Rails.cache when memory state is nil' do
          Rails.cache.write('dhan:totp_cooldown_until', 2.hours.from_now)
          described_class.instance_variable_set(:@totp_refresh_cooldown_until, nil)

          expect(described_class.send(:totp_cooldown_active?)).to be true
          expect(described_class.instance_variable_get(:@totp_refresh_cooldown_until)).not_to be_nil
        end

        it 'cleans up expired cooldown from Rails.cache' do
          Rails.cache.write('dhan:totp_cooldown_until', 2.hours.ago)
          described_class.instance_variable_set(:@totp_refresh_cooldown_until, nil)

          expect(described_class.send(:totp_cooldown_active?)).to be false
          expect(Rails.cache.read('dhan:totp_cooldown_until')).to be_nil
        end
      end

      it 'sets 12h cooldown and returns ENV token when Too many attempts and ENV token present' do
        allow(ENV).to receive(:[]).and_call_original
        allow(ENV).to receive(:[]).with('DHAN_CLIENT_ID').and_return('1000000001')
        allow(ENV).to receive(:[]).with('CLIENT_ID').and_return(nil)
        allow(ENV).to receive(:[]).with('DHAN_PIN').and_return('123456')
        allow(ENV).to receive(:[]).with('DHAN_TOTP_SECRET').and_return('BASE32SECRET')
        allow(ENV).to receive(:[]).with('DHAN_ACCESS_TOKEN').and_return('env_fallback_token')
        allow(ENV).to receive(:[]).with('ACCESS_TOKEN').and_return(nil)
        allow(DhanHQ::Auth).to receive(:generate_totp).with('BASE32SECRET').and_return('123456')
        allow(DhanHQ::Auth).to receive(:generate_access_token).and_return(
          { 'status' => 'error', 'message' => 'Too many attempts. Please try again after sometime.' }
        )

        token = described_class.refresh!(force: true)

        expect(token).to eq('env_fallback_token')
        expect(described_class.send(:totp_cooldown_active?)).to be true
      end

      it 'does not call API again within cooldown when ENV token present' do
        allow(ENV).to receive(:[]).and_call_original
        allow(ENV).to receive(:[]).with('DHAN_CLIENT_ID').and_return('1000000001')
        allow(ENV).to receive(:[]).with('CLIENT_ID').and_return(nil)
        allow(ENV).to receive(:[]).with('DHAN_PIN').and_return('123456')
        allow(ENV).to receive(:[]).with('DHAN_TOTP_SECRET').and_return('BASE32SECRET')
        allow(ENV).to receive(:[]).with('DHAN_ACCESS_TOKEN').and_return('env_token')
        allow(ENV).to receive(:[]).with('ACCESS_TOKEN').and_return(nil)
        allow(DhanHQ::Auth).to receive(:generate_totp).with('BASE32SECRET').and_return('123456')
        allow(DhanHQ::Auth).to receive(:generate_access_token).and_return(
          { 'status' => 'error', 'message' => 'Too many attempts. Please try again after sometime.' }
        )

        described_class.refresh!(force: true)
        expect(DhanHQ::Auth).to have_received(:generate_access_token).once

        token = described_class.refresh!(force: true)
        expect(token).to eq('env_token')
        expect(DhanHQ::Auth).to have_received(:generate_access_token).once
      end
    end

    context 'when API returns snake_case success' do
      it 'parses access_token and expires_at' do
        allow(ENV).to receive(:[]).and_call_original
        allow(ENV).to receive(:[]).with('DHAN_CLIENT_ID').and_return('1000000002')
        allow(ENV).to receive(:[]).with('CLIENT_ID').and_return(nil)
        allow(ENV).to receive(:[]).with('DHAN_PIN').and_return('123456')
        allow(ENV).to receive(:[]).with('DHAN_TOTP_SECRET').and_return('BASE32SECRET')
        allow(DhanHQ::Auth).to receive(:generate_totp).with('BASE32SECRET').and_return('123456')
        allow(DhanHQ::Auth).to receive(:generate_access_token).and_return(
          {
            'access_token' => 'snake_token',
            'client_id' => '1000000002',
            'expires_at' => 2.hours.from_now.iso8601
          }
        )

        token = described_class.refresh!(force: true)

        expect(token).to eq('snake_token')
        record = DhanAccessToken.first
        expect(record&.token).to eq('snake_token')
      end
    end

    context 'when cached token has nil expiry_time' do
      it 'does not raise NoMethodError and attempts refresh' do
        described_class.instance_variable_set(:@cached_token, { token: 'nil_exp_token', expiry_time: nil })
        described_class.instance_variable_set(:@cached_at, Time.current)
        allow(described_class).to receive(:refresh!).and_return(nil)

        expect { described_class.current_token! }.not_to raise_error
        expect(described_class.current_token!).to be_nil
      end
    end

    context 'when token exists and is not expiring soon' do
      it 'returns existing token without refreshing' do
        DhanAccessToken.create!(token: 'existing', expiry_time: 2.hours.from_now)
        allow(described_class).to receive(:refresh!).and_call_original

        token = described_class.current_token!

        expect(token).to eq('existing')
      end
    end
  end

  describe '.snapshot' do
    it 'returns the stored live token with its expiry and never refreshes' do
      expiry = 4.hours.from_now.change(usec: 0)
      DhanAccessToken.create!(token: 'stored-token', expiry_time: expiry)
      allow(described_class).to receive(:refresh!)

      snapshot = described_class.snapshot

      expect(snapshot).to include(token: 'stored-token', expiry_time: expiry)
      expect(described_class).not_to have_received(:refresh!)
    end

    it 'returns nil for an expired token instead of refreshing it' do
      DhanAccessToken.create!(token: 'stale-token', expiry_time: 1.minute.ago)
      allow(described_class).to receive(:refresh!)

      expect(described_class.snapshot).to be_nil
      expect(described_class).not_to have_received(:refresh!)
    end

    it 'returns nil when there is no token at all' do
      expect(described_class.snapshot).to be_nil
    end
  end
end
