# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Options::CalibrationNotifier do
  let(:run) do
    CalibrationRun.create!(
      symbol: 'NIFTY', weeks_analyzed: 52, strike_mode: 'atm_plus_minus',
      raw_stats: { 'avg_gain' => 14.2, 'avg_retrace_abs' => 3.1 },
      proposed_patch: { 'risk' => { 'percentage_pnl_exit' => { 'target_pct' => 0.064 } } },
      is_regime_shift: false
    )
  end

  let(:telegram_client) { instance_double(Notifications::TelegramNotifier, send_message: true, enabled?: true) }

  before do
    allow(Notifications::TelegramNotifier).to receive(:instance).and_return(telegram_client)
  end

  describe '.notify' do
    it 'sends a Telegram message' do
      described_class.notify('NIFTY', run)
      expect(telegram_client).to have_received(:send_message).once
    end

    it 'includes symbol in the message' do
      described_class.notify('NIFTY', run)
      expect(telegram_client).to have_received(:send_message).with(a_string_including('NIFTY'))
    end

    it 'includes weeks and strike_mode in the message' do
      described_class.notify('NIFTY', run)
      expect(telegram_client).to have_received(:send_message)
        .with(a_string_including('52').and(a_string_including('atm_plus_minus')))
    end

    it 'includes dot-notation patch key in the message' do
      described_class.notify('NIFTY', run)
      expect(telegram_client).to have_received(:send_message)
        .with(a_string_including('risk.percentage_pnl_exit.target_pct'))
    end

    it 'includes Apply instruction in the message' do
      described_class.notify('NIFTY', run)
      expect(telegram_client).to have_received(:send_message).with(a_string_including('Apply'))
    end

    context 'when run is a regime shift' do
      let(:run) do
        CalibrationRun.create!(
          symbol: 'NIFTY', weeks_analyzed: 52, strike_mode: 'atm_plus_minus',
          raw_stats: {}, proposed_patch: {}, is_regime_shift: true,
          regime_reason: 'avg_retrace_abs: 12.0 is 3.2σ higher than historical mean'
        )
      end

      it 'includes the regime shift warning in the message' do
        described_class.notify('NIFTY', run)
        expect(telegram_client).to have_received(:send_message)
          .with(a_string_including('Regime shift'))
      end
    end

    it 'does not raise when Telegram fails' do
      allow(telegram_client).to receive(:send_message).and_raise(StandardError, 'network error')
      expect { described_class.notify('NIFTY', run) }.not_to raise_error
    end
  end

  describe '.notify_error' do
    it 'sends an error notification without raising' do
      expect { described_class.notify_error('NIFTY', StandardError.new('oops')) }.not_to raise_error
    end
  end
end
