# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Research::ContextClassifier do
  def series_with(candles_attrs, interval: '1')
    series = CandleSeries.new(symbol: 'NIFTY', interval: interval)
    candles_attrs.each do |attrs|
      series.add_candle(Candle.new(**attrs))
    end
    series
  end

  def flat_candle(minute, price:, volume: 1000)
    {
      timestamp: Time.zone.parse('2026-07-10 09:15:00') + minute.minutes,
      open: price, high: price, low: price, close: price, volume: volume
    }
  end

  describe '.classify' do
    it 'returns {} for an empty series' do
      expect(described_class.classify(series: CandleSeries.new(symbol: 'NIFTY'))).to eq({})
    end

    it 'returns "unknown" for buckets that need more history than a short series has' do
      series = series_with([flat_candle(0, price: 100), flat_candle(1, price: 101)])

      result = described_class.classify(series: series)

      # ATR/volume both have explicit minimum-candle guards this asserts against;
      # RSI's behavior on too little data depends on the underlying TA gem and
      # isn't pinned here.
      expect(result['volatility_regime']).to eq('unknown')
      expect(result['volume_regime']).to eq('unknown')
    end

    it 'buckets time_context from the last candle timestamp (IST)' do
      opening = series_with([flat_candle(5, price: 100)]) # 09:20 -> opening_range
      midday = series_with([{ timestamp: Time.zone.parse('2026-07-10 12:00:00'), open: 100, high: 100, low: 100,
                               close: 100, volume: 1000 }])

      expect(described_class.classify(series: opening)['time_context']).to eq('opening_range')
      expect(described_class.classify(series: midday)['time_context']).to eq('midday')
    end

    it 'classifies vwap_relation from close vs the volume-weighted average price' do
      # equal volumes -> vwap is the simple average of typical prices; a close well
      # above that average should read as above_vwap.
      candles = (0..10).map { |i| flat_candle(i, price: 100) }
      candles << { timestamp: Time.zone.parse('2026-07-10 09:26:00'), open: 100, high: 110, low: 108, close: 110,
                   volume: 1000 }
      series = series_with(candles)

      expect(described_class.classify(series: series)['vwap_relation']).to eq('above_vwap')
    end

    it 'classifies opening_range_breakout using bars fetched independently of the main series' do
      series = series_with([flat_candle(120, price: 130)]) # well past the opening range
      opening_range_bars = [
        double(high: 105.0, low: 95.0, open: 100.0) # rubocop:disable RSpec/VerifiedDoubles
      ]

      result = described_class.classify(series: series, opening_range_bars: opening_range_bars)
      expect(result['opening_range_breakout']).to eq('breakout_up')
    end

    it 'returns unknown ORB classification when no opening-range bars were supplied' do
      series = series_with([flat_candle(0, price: 100)])
      expect(described_class.classify(series: series)['opening_range_breakout']).to eq('unknown')
    end

    it 'classifies a gap from the opening bar vs the previous session close' do
      opening_range_bars = [double(high: 205.0, low: 195.0, open: 200.0)] # rubocop:disable RSpec/VerifiedDoubles
      series = series_with([flat_candle(0, price: 200)])

      up = described_class.classify(series: series, opening_range_bars: opening_range_bars,
                                     previous_session_close: 190.0)
      down = described_class.classify(series: series, opening_range_bars: opening_range_bars,
                                       previous_session_close: 210.0)
      none = described_class.classify(series: series, opening_range_bars: opening_range_bars,
                                       previous_session_close: 200.1)

      expect(up['gap']).to eq('gap_up')
      expect(down['gap']).to eq('gap_down')
      expect(none['gap']).to eq('none')
    end

    it 'classifies volume_regime relative to the trailing average' do
      baseline = (0..18).map { |i| flat_candle(i, price: 100, volume: 1000) }
      spike = flat_candle(19, price: 100, volume: 3000)
      series = series_with(baseline + [spike])

      expect(described_class.classify(series: series)['volume_regime']).to eq('volume_spike')
    end

    it 'delegates market structure / liquidity sweep to Smc::Detectors and always includes the keys' do
      candles = (0..40).map { |i| flat_candle(i, price: 100 + i) } # steadily rising, no swings
      series = series_with(candles)

      result = described_class.classify(series: series)

      expect(result).to have_key('market_structure')
      expect(result).to have_key('recent_bos')
      expect(result).to have_key('recent_choch')
      expect(result).to have_key('liquidity_sweep')
      expect(%w[buy_side_sweep sell_side_sweep none]).to include(result['liquidity_sweep'])
    end
  end
end
