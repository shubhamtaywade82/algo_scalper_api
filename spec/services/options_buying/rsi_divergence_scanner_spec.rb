# frozen_string_literal: true

require 'rails_helper'

RSpec.describe OptionsBuying::RsiDivergenceScanner do
  subject(:scanner) { described_class.new(index_key: 'NIFTY') }

  describe '#detect_divergence' do
    # 20-point windows; indices line up across highs/lows/rsi_values.
    it 'flags BEARISH on a higher price high with a lower RSI high' do
      highs = Array.new(20, 90.0)
      highs[5] = 100.0   # prior swing high
      highs[19] = 110.0  # recent, higher high
      lows = Array.new(20, 80.0)
      rsi = Array.new(20, 50.0)
      rsi[5] = 80.0      # prior RSI high
      rsi[19] = 60.0     # recent RSI lower → bearish divergence

      expect(scanner.send(:detect_divergence, highs, lows, rsi)).to eq(described_class::BEARISH)
    end

    it 'flags BULLISH on a lower price low with a higher RSI low' do
      highs = Array.new(20, 100.0) # flat → no bearish high divergence
      lows = Array.new(20, 95.0)
      lows[5] = 90.0     # prior swing low
      lows[19] = 80.0    # recent, lower low
      rsi = Array.new(20, 50.0)
      rsi[5] = 40.0      # prior RSI low
      rsi[19] = 55.0     # recent RSI higher → bullish divergence

      expect(scanner.send(:detect_divergence, highs, lows, rsi)).to eq(described_class::BULLISH)
    end

    it 'returns NEUTRAL when price and RSI move together' do
      highs = (1..20).map { |i| 100.0 + i }
      lows  = (1..20).map { |i| 90.0 + i }
      rsi   = (1..20).map { |i| 40.0 + i }

      expect(scanner.send(:detect_divergence, highs, lows, rsi)).to eq(described_class::NEUTRAL)
    end
  end

  describe '#wilder_rsi_series' do
    it 'returns one value per close with a leading warmup of nils' do
      closes = (1..30).map(&:to_f)
      series = scanner.send(:wilder_rsi_series, closes, 14)

      expect(series.size).to eq(30)
      expect(series.first(14)).to all(be_nil)
      expect(series[14]).to be_a(Float)
    end

    it 'reads high for an uptrend and low for a downtrend' do
      # mostly-up / mostly-down with small pullbacks (pure trends give avg_loss/gain 0,
      # which this codebase maps to a neutral 50 — see Trading::Indicators#rsi).
      v = 100.0
      up_closes = (1..30).map { |i| v += (i % 5).zero? ? -1.0 : 3.0 }
      v = 100.0
      down_closes = (1..30).map { |i| v += (i % 5).zero? ? 1.0 : -3.0 }

      expect(scanner.send(:wilder_rsi_series, up_closes, 14).last).to be > 70
      expect(scanner.send(:wilder_rsi_series, down_closes, 14).last).to be < 30
    end
  end

  describe '#scan!' do
    it 'returns NEUTRAL when the rsi_bias feature is disabled' do
      allow(OptionsBuying::Mode).to receive(:rsi_bias_enabled?).and_return(false)
      expect(scanner.scan!).to eq(described_class::NEUTRAL)
    end

    it 'returns NEUTRAL when there are too few candles' do
      allow(OptionsBuying::Mode).to receive_messages(rsi_bias_enabled?: true, config: {})
      idx = { key: 'NIFTY', sid: '13', segment: 'IDX_I' }
      allow(IndexConfigLoader).to receive(:load_indices).and_return([idx])
      instrument = instance_double(Instrument)
      allow(Instrument).to receive(:find_by).and_return(instrument)
      series = instance_double(CandleSeries, candles: Array.new(5))
      allow(instrument).to receive(:candle_series).and_return(series)

      expect(scanner.scan!).to eq(described_class::NEUTRAL)
    end
  end
end
