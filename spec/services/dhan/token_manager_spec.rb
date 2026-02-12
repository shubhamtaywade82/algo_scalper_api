# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Dhan::TokenManager do
  describe '.current_token!' do
    context 'when no token exists' do
      it 'generates and persists a token' do
        allow(ENV).to receive(:fetch).with('CLIENT_ID').and_return('1000000001')
        allow(ENV).to receive(:[]).with('DHAN_CLIENT_ID').and_return(nil)
        allow(ENV).to receive(:fetch).with('DHAN_PIN').and_return('123456')
        allow(ENV).to receive(:fetch).with('DHAN_TOTP_SECRET').and_return('BASE32SECRET')

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

