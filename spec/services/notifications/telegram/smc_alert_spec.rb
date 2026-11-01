# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Notifications::Telegram::SmcAlert do
  let(:instrument) { instance_double(Instrument, symbol_name: 'NIFTY') }
  let(:signal) do
    instance_double(
      Smc::SignalEvent,
      instrument: instrument,
      decision: :call,
      timeframe: '5m',
      price: 25_000.0,
      reasons: ['Bullish BOS on 5m', 'Order block mitigation'],
      ai_analysis: nil
    )
  end
  let(:client) { instance_double(Notifications::Telegram::Client) }
  let(:alerter) { described_class.new(signal) }

  before do
    allow(Notifications::Telegram::Client).to receive(:new).and_return(client)
    allow(client).to receive(:send_message).and_return(true)
    allow(AlgoConfig).to receive(:fetch).and_return(
      telegram: { enabled: true, smc_alert_cooldown_minutes: 30, smc_max_alerts_per_session: 2 }
    )
    allow(ENV).to receive(:fetch).with('TELEGRAM_BOT_TOKEN').and_return('TOKEN')
    allow(ENV).to receive(:fetch).with('TELEGRAM_CHAT_ID').and_return('CHAT')
    allow(ENV).to receive(:[]).and_call_original
    allow(ENV).to receive(:[]).with('TELEGRAM_BOT_TOKEN').and_return('TOKEN')
    allow(ENV).to receive(:[]).with('TELEGRAM_CHAT_ID').and_return('CHAT')
    allow(Rails.logger).to receive(:debug)
    allow(Rails.logger).to receive(:info)
    allow(Rails.logger).to receive(:warn)
    allow(Rails.cache).to receive_messages(read: nil, write: true)
    allow(signal).to receive(:valid?).and_return(true)
  end

  describe '#notify!' do
    context 'when signal is invalid' do
      before { allow(signal).to receive(:valid?).and_return(false) }

      it 'returns nil without sending' do
        expect(client).not_to receive(:send_message)
        expect(alerter.notify!).to be_nil
      end
    end

    context 'when telegram is disabled' do
      before do
        allow(AlgoConfig).to receive(:fetch).and_return(
          telegram: { enabled: false }
        )
      end

      it 'returns nil without sending' do
        expect(client).not_to receive(:send_message)
        expect(alerter.notify!).to be_nil
      end
    end

    context 'when telegram env vars are missing' do
      before do
        allow(ENV).to receive(:[]).with('TELEGRAM_BOT_TOKEN').and_return(nil)
      end

      it 'returns nil without sending' do
        expect(client).not_to receive(:send_message)
        expect(alerter.notify!).to be_nil
      end
    end

    context 'when duplicate alert (same price within 0.1%)' do
      before do
        allow(Rails.cache).to receive(:read).with('smc:alert:NIFTY:call').and_return(
          { price: 25_010.0, sent_at: Time.current.to_i, decision: :call }
        )
      end

      it 'returns nil without sending' do
        expect(client).not_to receive(:send_message)
        expect(alerter.notify!).to be_nil
      end
    end

    context 'when cooldown is active' do
      before do
        # Different price (so duplicate check passes), but recent sent_at (so cooldown fires)
        allow(Rails.cache).to receive(:read).with('smc:alert:NIFTY:call').and_return(
          { price: 24_000.0, sent_at: (Time.current - 60).to_i, decision: :call }
        )
      end

      it 'returns nil without sending' do
        expect(client).not_to receive(:send_message)
        expect(alerter.notify!).to be_nil
      end
    end

    context 'when max alerts per session reached' do
      before do
        # Duplicate check: different price, so duplicate check passes
        allow(Rails.cache).to receive(:read).with('smc:alert:NIFTY:call').and_return(
          { price: 24_000.0, sent_at: (Time.current - 3600).to_i, decision: :call }
        )
        # Cooldown check: same data above — 1 hour ago, so cooldown passes
        # Session check: 2 prior :call alerts (max is 2)
        allow(Rails.cache).to receive(:read).with("smc:session:NIFTY:#{Time.zone.today}").and_return(
          [
            { decision: :call, price: 24_000.0, sent_at: (Time.current - 7200).to_i },
            { decision: :call, price: 24_200.0, sent_at: (Time.current - 5400).to_i }
          ]
        )
      end

      it 'returns nil without sending' do
        expect(client).not_to receive(:send_message)
        expect(alerter.notify!).to be_nil
      end
    end

    context 'when send_message fails' do
      before do
        allow(client).to receive(:send_message).and_return(false)
      end

      it 'does not record the alert' do
        expect(Rails.cache).not_to receive(:write)
        alerter.notify!
      end
    end

    context 'with all checks passing' do
      it 'sends the message and records the alert in cache' do
        expect(client).to receive(:send_message) do |msg|
          expect(msg).to include('SMC + AVRZ')
          expect(msg).to include('NIFTY')
          expect(msg).to include('CALL')
          expect(msg).to include('5m')
          expect(msg).to include('25000.0')
          true
        end
        expect(Rails.cache).to receive(:write).twice
        alerter.notify!
      end
    end

    context 'with ai_analysis present' do
      before do
        allow(signal).to receive(:ai_analysis).and_return('Strong bullish bias detected by LLM analysis.')
      end

      it 'includes AI analysis section in the message' do
        expect(client).to receive(:send_message) do |msg|
          expect(msg).to include('AI Analysis')
          expect(msg).to include('Strong bullish bias')
          true
        end
        alerter.notify!
      end
    end

    context 'with no_trade decision and ai_analysis' do
      before do
        allow(signal).to receive_messages(decision: :no_trade, ai_analysis: 'No clear edge in current regime.', valid?: true)
      end

      it 'uses ANALYSIS label instead of SIGNAL' do
        expect(client).to receive(:send_message) do |msg|
          expect(msg).to include('ANALYSIS')
          true
        end
        alerter.notify!
      end
    end

    context 'with html-special characters in reasons' do
      before do
        allow(signal).to receive(:reasons).and_return(['Bullish <BOS> & breakdown'])
      end

      it 'escapes HTML special characters' do
        expect(client).to receive(:send_message) do |msg|
          expect(msg).to include('&lt;BOS&gt;')
          expect(msg).to include('&amp;')
          true
        end
        alerter.notify!
      end
    end

    context 'with instrument that exposes an option chain' do
      before do
        allow(instrument).to receive(:respond_to?).with(:fetch_option_chain).and_return(true)
        allow(instrument).to receive_messages(fetch_option_chain: { last_price: 25_000.0,
                                                                    oc: {
            '25000.000000' => { 'ce' => { 'last_price' => 120.0, 'implied_volatility' => 0.15, 'oi' => 1_000_000 }, 'pe' => { 'last_price' => 110.0, 'implied_volatility' => 0.14, 'oi' => 900_000 } },
            '25050.000000' => { 'ce' => { 'last_price' => 95.0,  'implied_volatility' => 0.16, 'oi' => 800_000 }, 'pe' => { 'last_price' => 130.0, 'implied_volatility' => 0.15, 'oi' => 850_000 } }
          } }, lot_size_from_derivatives: nil)
        allow(IndexConfigLoader).to receive(:load_indices).and_return([
                                                                        { key: 'NIFTY', lot_size: 75 }
                                                                      ])
      end

      it 'includes strikes section with ATM, CALL, PUT, Suggested Qty' do
        expect(client).to receive(:send_message) do |msg|
          expect(msg).to include('Option Strikes')
          expect(msg).to include('ATM:')
          expect(msg).to include('CALL:')
          expect(msg).to include('PUT:')
          expect(msg).to include('Suggested Qty')
          expect(msg).to include('75')
          true
        end
        alerter.notify!
      end
    end

    context 'when fetch_option_chain raises' do
      before do
        allow(instrument).to receive(:respond_to?).with(:fetch_option_chain).and_return(true)
        allow(instrument).to receive(:fetch_option_chain).and_raise(StandardError, 'api down')
      end

      it 'still sends the alert (without strikes section)' do
        expect(client).to receive(:send_message) do |msg|
          expect(msg).not_to include('Option Strikes')
          true
        end
        alerter.notify!
      end
    end
  end

  describe 'cooldown configuration' do
    it 'uses configured value when set' do
      allow(AlgoConfig).to receive(:fetch).and_return(
        telegram: { enabled: true, smc_alert_cooldown_minutes: 45 }
      )
      expect(Rails.cache).to receive(:write).with(
        'smc:alert:NIFTY:call',
        anything,
        hash_including(expires_in: 45.minutes)
      )
      expect(Rails.cache).to receive(:write).with(
        "smc:session:NIFTY:#{Time.zone.today}",
        anything,
        hash_including(expires_at: Time.zone.tomorrow.beginning_of_day)
      )
      alerter.notify!
    end

    it 'default COOLDOWN_MINUTES constant is 30' do
      expect(Notifications::Telegram::SmcAlert::COOLDOWN_MINUTES).to eq(30)
    end
  end
end
