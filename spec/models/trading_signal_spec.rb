# frozen_string_literal: true

require 'rails_helper'

RSpec.describe TradingSignal do
  let(:signal) do
    create(:trading_signal,
           index_key: 'NIFTY',
           direction: 'bullish',
           timeframe: '1m',
           supertrend_value: 23_440,
           adx_value: 20.4,
           candle_timestamp: 1.minute.ago,
           signal_timestamp: Time.current,
           metadata: {})
  end

  describe '.create_from_analysis' do
    it 'persists slim metadata to db and full diagnostic payload to redis' do
      full_metadata = {
        regime: 'RANGING',
        strategy: 'supertrend_adx',
        mtf_rsi: { '1m' => 44.0 }
      }

      signal = described_class.create_from_analysis(
        index_key: 'NIFTY',
        direction: 'bullish',
        timeframe: '1m',
        supertrend_value: 22_000,
        adx_value: 18.5,
        candle_timestamp: 1.minute.ago,
        metadata: full_metadata
      )

      expect(signal.metadata).to include('regime' => 'RANGING', 'strategy' => 'supertrend_adx')
      expect(signal.metadata).not_to have_key('mtf_rsi')
      expect(Signal::LiveMetadataCache.instance.fetch(signal.id)).to include(
        'regime' => 'RANGING',
        'mtf_rsi' => { '1m' => 44.0 }
      )
      expect(signal.effective_metadata).to include('mtf_rsi' => { '1m' => 44.0 })
    end

    it 'stamps the effective config version on the persisted metadata' do
      signal = described_class.create_from_analysis(
        index_key: 'NIFTY',
        direction: 'bullish',
        timeframe: '1m',
        supertrend_value: 22_000,
        adx_value: 18.5,
        candle_timestamp: 1.minute.ago,
        metadata: { regime: 'TRENDING' }
      )

      expect(signal.metadata['config_version']).to include('hash')
    end
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

    it 'merges extra_metadata with string keys for skip diagnostics' do
      signal.record_entry_outcome(
        'skipped',
        'strike_selection: no legs',
        extra_metadata: { 'entry_skip_stage' => 'strike_selection', 'entry_skip_code' => 'no_legs_after_filter' }
      )

      signal.reload
      expect(signal.metadata['entry_blocked_reason']).to eq('strike_selection: no legs')
      expect(signal.metadata['entry_skip_stage']).to eq('strike_selection')
      expect(signal.metadata['entry_skip_code']).to eq('no_legs_after_filter')
    end

    it 'is a no-op when called on nil (safe navigation at call sites)' do
      nil_signal = nil
      expect { nil_signal&.record_entry_outcome('blocked', 'reason') }.not_to raise_error
    end
  end
end
