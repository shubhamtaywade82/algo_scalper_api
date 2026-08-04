# frozen_string_literal: true

require 'rails_helper'

RSpec.describe TradingSignal do
  let(:signal) do
    create(:trading_signal,
           index_key: 'NIFTY',
           direction: 'bullish',
           timeframe: '1m',
           supertrend_value: 23440,
           adx_value: 20.4,
           candle_timestamp: 1.minute.ago,
           signal_timestamp: Time.current,
           metadata: {})
  end

  describe '#record_entry_outcome' do
    it 'sets entry_outcome to entered and does not set entry_blocked_reason' do
      signal.record_entry_outcome('entered')

      signal.reload
      expect(signal.metadata['entry_outcome']).to eq('entered')
      expect(signal.metadata).not_to have_key('entry_blocked_reason')
    end

    it 'sets both fields when outcome is blocked' do
      signal.record_entry_outcome('blocked', 'cooldown active for index NIFTY')

      signal.reload
      expect(signal.metadata['entry_outcome']).to eq('blocked')
      expect(signal.metadata['entry_blocked_reason']).to eq('cooldown active for index NIFTY')
    end

    it 'sets both fields when outcome is skipped' do
      signal.record_entry_outcome('skipped', 'no suitable strikes')

      signal.reload
      expect(signal.metadata['entry_outcome']).to eq('skipped')
      expect(signal.metadata['entry_blocked_reason']).to eq('no suitable strikes')
    end

    it 'overwrites a prior blocked outcome when called again with entered (last-write-wins)' do
      signal.record_entry_outcome('blocked', 'circuit breaker tripped')
      signal.record_entry_outcome('entered')

      signal.reload
      expect(signal.metadata['entry_outcome']).to eq('entered')
      expect(signal.metadata).not_to have_key('entry_blocked_reason')
    end

    it 'preserves other metadata keys already on the signal' do
      signal.update!(metadata: { 'strategy' => 'supertrend_adx' })

      signal.record_entry_outcome('skipped', 'missing ATR')

      signal.reload
      expect(signal.metadata['strategy']).to eq('supertrend_adx')
      expect(signal.metadata['entry_outcome']).to eq('skipped')
    end

    it 'is a no-op when called on nil (safe navigation at call sites)' do
      nil_signal = nil
      expect { nil_signal&.record_entry_outcome('blocked', 'reason') }.not_to raise_error
    end
  end
end
