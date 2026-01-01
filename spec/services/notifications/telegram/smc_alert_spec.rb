# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Notifications::Telegram::SmcAlert do
  describe '#notify!' do
    it 'skips when telegram env is missing' do
      original_token = ENV.delete('TELEGRAM_BOT_TOKEN')
      original_chat_id = ENV.delete('TELEGRAM_CHAT_ID')

      instrument = instance_double('Instrument', symbol_name: 'NIFTY')
      signal = Smc::SignalEvent.new(
        instrument: instrument,
        decision: :call,
        timeframe: '5m',
        price: 100,
        reasons: ['AVRZ rejection confirmed']
      )

      expect(Notifications::Telegram::Client).not_to receive(:new)
      expect(described_class.new(signal).notify!).to be_nil
    ensure
      ENV['TELEGRAM_BOT_TOKEN'] = original_token if original_token
      ENV['TELEGRAM_CHAT_ID'] = original_chat_id if original_chat_id
    end

    it 'sends a formatted message when configured' do
      original_token = ENV['TELEGRAM_BOT_TOKEN']
      original_chat_id = ENV['TELEGRAM_CHAT_ID']

      ENV['TELEGRAM_BOT_TOKEN'] = 'token'
      ENV['TELEGRAM_CHAT_ID'] = 'chat'

      instrument = instance_double('Instrument', symbol_name: 'BANKNIFTY')
      signal = Smc::SignalEvent.new(
        instrument: instrument,
        decision: :put,
        timeframe: '5m',
        price: 123.45,
        reasons: ['HTF in Premium (Supply)', 'Liquidity sweep on 5m (buy_side)']
      )

      client = instance_double('Notifications::Telegram::Client')
      allow(Notifications::Telegram::Client).to receive(:new).and_return(client)

      expect(client).to receive(:send_message) do |text|
        expect(text).to include('*SMC + AVRZ SIGNAL*')
        expect(text).to include('*Instrument*: BANKNIFTY')
        expect(text).to include('*Action*: PUT')
        expect(text).to include('• HTF in Premium (Supply)')
      end

      described_class.new(signal).notify!
    ensure
      ENV['TELEGRAM_BOT_TOKEN'] = original_token
      ENV['TELEGRAM_CHAT_ID'] = original_chat_id
    end
  end
end

