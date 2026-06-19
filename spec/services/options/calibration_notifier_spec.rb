# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Options::CalibrationNotifier do
  let(:run) do
    CalibrationRun.create!(
      symbol: 'NIFTY',
      weeks_analyzed: 52,
      strike_mode: 'atm_plus_minus',
      raw_stats: { 'avg_gain' => 14.2, 'avg_retrace_abs' => 3.1 },
      proposed_patch: { 'risk' => { 'percentage_pnl_exit' => { 'target_pct' => 0.064 } } },
      is_regime_shift: false
    )
  end

  let(:telegram) { instance_double(Notifications::TelegramNotifier, enabled?: true, send_message: true) }

  before do
    allow(Notifications::TelegramNotifier).to receive(:instance).and_return(telegram)
  end

  describe '.notify' do
    it 'sends a Telegram message' do
      described_class.notify('NIFTY', run)
      expect(telegram).to have_received(:send_message).once
    end

    it 'does not raise when Telegram fails' do
      allow(telegram).to receive(:send_message).and_raise(StandardError, 'network error')
      expect { described_class.notify('NIFTY', run) }.not_to raise_error
    end
  end

  describe '.notify_error' do
    it 'sends an error notification without raising' do
      expect { described_class.notify_error('NIFTY', StandardError.new('oops')) }.not_to raise_error
    end
  end
end
