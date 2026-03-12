# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Dhan::TokenManager do
  before do
    described_class.instance_variable_set(:@cached_token, nil)
    described_class.instance_variable_set(:@creds, nil)
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
      it 'returns nil and logs the message' do
        allow(ENV).to receive(:[]).and_call_original
        allow(ENV).to receive(:[]).with('DHAN_CLIENT_ID').and_return('1000000001')
        allow(ENV).to receive(:[]).with('CLIENT_ID').and_return(nil)
        allow(ENV).to receive(:[]).with('DHAN_PIN').and_return('123456')
        allow(ENV).to receive(:[]).with('DHAN_TOTP_SECRET').and_return('BASE32SECRET')
        allow(DhanHQ::Auth).to receive(:generate_totp).with('BASE32SECRET').and_return('123456')
        allow(DhanHQ::Auth).to receive(:generate_access_token).and_return(
          { 'status' => 'error', 'message' => 'Too many attempts. Please try again after sometime.' }
        )

        token = described_class.refresh!(force: true)

        expect(token).to be_nil
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

    context 'when token exists and is not expiring soon' do
      it 'returns existing token without refreshing' do
        DhanAccessToken.create!(token: 'existing', expiry_time: 2.hours.from_now)
        allow(described_class).to receive(:refresh!).and_call_original

        token = described_class.current_token!

        expect(token).to eq('existing')
      end
    end
  end
end
