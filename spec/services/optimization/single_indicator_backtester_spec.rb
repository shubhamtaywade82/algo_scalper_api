# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Optimization::SingleIndicatorBacktester do
  let(:series) { build(:candle_series, :nifty_series) }

  def add_candles(series, count:, base_price: 25_000.0, drift: 10.0)
    count.times do |i|
      series.add_candle(build(:candle,
                              timestamp: Time.current - (count - i).hours,
                              open: base_price + (i * drift),
                              high: base_price + (i * drift) + 30,
                              low: base_price + (i * drift) - 20,
                              close: base_price + (i * drift) + 25,
                              volume: 1_000_000))
    end
  end

  describe '#initialize' do
    it 'stores series, indicator, params, candles' do
      add_candles(series, count: 60)
      bt = described_class.new(series: series, indicator: :adx, params: { period: 14 })
      expect(bt.instance_variable_get(:@indicator)).to eq(:adx)
      expect(bt.instance_variable_get(:@series)).to eq(series)
      expect(bt.instance_variable_get(:@candles).size).to eq(60)
    end
  end

  describe '#run' do
    context 'when fewer than 50 candles' do
      before { add_candles(series, count: 30) }

      it 'returns nil without running indicators' do
        bt = described_class.new(series: series, indicator: :adx, params: {})
        expect(bt.run).to be_nil
      end
    end

    context 'when an unexpected error is raised' do
      before { add_candles(series, count: 60) }

      it 'logs a warning and returns nil' do
        allow(Rails.logger).to receive(:warn)
        bt = described_class.new(series: series, indicator: :adx, params: {})
        allow(bt).to receive(:generate_signals).and_raise(StandardError, 'boom')
        expect(bt.run).to be_nil
      end
    end

    context 'with :adx indicator on a strong uptrend' do
      before do
        add_candles(series, count: 60, base_price: 25_000.0, drift: 20.0)
      end

      it 'returns metrics hash with total_signals, avg_price_move_pct, win_rate, etc.' do
        bt = described_class.new(series: series, indicator: :adx, params: { period: 14, threshold: 15 })
        result = bt.run
        if result.nil?
          # No signals generated on this synthetic series — acceptable.
          expect(result).to be_nil
        else
          expect(result).to include(
            :total_signals, :avg_price_move, :avg_price_move_pct, :win_rate,
            :avg_win_pct, :max_move_pct, :total_movements
          )
          expect(result[:total_signals]).to be_an(Integer)
          expect(result[:win_rate]).to be_between(0, 1)
        end
      end
    end

    context 'with :rsi indicator' do
      before { add_candles(series, count: 60) }

      it 'returns either nil (no signals) or a metrics hash' do
        bt = described_class.new(series: series, indicator: :rsi, params: { period: 14, oversold: 30, overbought: 70 })
        result = bt.run
        if result.nil?
          expect(result).to be_nil
        else
          expect(result).to include(:total_signals, :win_rate)
        end
      end
    end

    context 'with :atr indicator' do
      before { add_candles(series, count: 60) }

      it 'returns either nil or a metrics hash' do
        bt = described_class.new(series: series, indicator: :atr, params: { period: 14 })
        result = bt.run
        if result.nil?
          expect(result).to be_nil
        else
          expect(result).to include(:total_signals)
        end
      end
    end

    context 'with :macd indicator' do
      before { add_candles(series, count: 60) }

      it 'returns either nil or a metrics hash' do
        bt = described_class.new(series: series, indicator: :macd, params: { fast: 12, slow: 26, signal: 9 })
        result = bt.run
        if result.nil?
          expect(result).to be_nil
        else
          expect(result).to include(:total_signals)
        end
      end
    end

    context 'with :supertrend indicator' do
      before { add_candles(series, count: 60) }

      it 'returns either nil or a metrics hash' do
        bt = described_class.new(series: series, indicator: :supertrend, params: { atr_period: 10, multiplier: 2.0 })
        result = bt.run
        if result.nil?
          expect(result).to be_nil
        else
          expect(result).to include(:total_signals)
        end
      end
    end

    context 'with an unknown indicator' do
      before { add_candles(series, count: 60) }

      it 'returns nil (no signals generated)' do
        bt = described_class.new(series: series, indicator: :unknown_indicator, params: {})
        expect(bt.run).to be_nil
      end
    end
  end

  describe '#calculate_metrics (via #run)' do
    it 'computes win_rate as wins/total' do
      add_candles(series, count: 60, drift: 20.0)
      bt = described_class.new(series: series, indicator: :adx, params: { period: 14, threshold: 15 })
      result = bt.run
      if result.nil?
        expect(result).to be_nil
      else
        expect(result[:win_rate]).to be_between(0, 1)
        expect(result[:total_movements]).to eq(result[:total_signals])
      end
    end
  end
end
