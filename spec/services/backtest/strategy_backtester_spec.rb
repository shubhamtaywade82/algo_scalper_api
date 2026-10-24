# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Backtest::StrategyBacktester do
  let(:file_path) { Rails.root.join("tmp/strategy_backtester_spec_strategy.rb").to_s }

  # Always buys once it has enough 1m history — deterministic entry timing,
  # avoids needing to reverse-engineer a real strategy's indicator thresholds.
  let(:strategy_source) do
    <<~RUBY
      class AlwaysBuyCallStrategy < Strategies::Base
        def call(context)
          series = context.candles.call("1m")
          return Signals::Hold.new(reason: "warming_up") unless series&.candles && series.candles.size >= 5

          Signals::BuyCall.new(confidence: 0.9, reason: "always_buy_test_strategy")
        end
      end
    RUBY
  end

  let(:strategy_record) { create(:strategy_record, slug: 'always-buy-call') }
  let(:strategy_version) do
    Strategies::Version.create!(
      strategy_record: strategy_record,
      version: 1,
      file_path: file_path,
      checksum: Digest::SHA256.hexdigest(strategy_source),
      manifest: { 'class_name' => 'AlwaysBuyCallStrategy', 'params' => {} },
      deployed_at: Time.current
    )
  end

  before { File.write(file_path, strategy_source) }

  after do
    FileUtils.rm_f(file_path)
    Object.send(:remove_const, :AlwaysBuyCallStrategy) if Object.const_defined?(:AlwaysBuyCallStrategy)
  end

  describe 'signal mapping (#map_signal)' do
    let!(:instrument) { create(:instrument, :nifty_index) }
    let(:backtester) do
      described_class.new(symbol: 'NIFTY', trading_type: :futures).tap do |b|
        b.send(:init_strategy!, strategy_version)
      end
    end
    let(:candle) { Candle.new(timestamp: Time.zone.parse('2026-07-06 10:00:00'), open: 100, high: 101, low: 99, close: 100.5, volume: 500) }

    it 'maps BuyCall to :long for futures at/above the confidence threshold' do
      signal = Signals::BuyCall.new(confidence: 0.9, reason: 'x')
      result = backtester.send(:map_signal, signal, candle)

      expect(result).to include(type: :long, price: 100.5)
      expect(result[:reason]).to include('always-buy-call@v1')
    end

    it 'maps BuyPut to :short for futures' do
      signal = Signals::BuyPut.new(confidence: 0.9, reason: 'x')
      result = backtester.send(:map_signal, signal, candle)

      expect(result[:type]).to eq(:short)
    end

    it 'maps BuyCall to :ce for options trading_type' do
      backtester.instance_variable_set(:@trading_type, :options)
      signal = Signals::BuyCall.new(confidence: 0.9, reason: 'x')

      expect(backtester.send(:map_signal, signal, candle)[:type]).to eq(:ce)
    end

    it 'returns nil for Hold' do
      expect(backtester.send(:map_signal, Signals::Hold.new, candle)).to be_nil
    end

    it 'returns nil when confidence is below the configured threshold' do
      signal = Signals::BuyCall.new(confidence: 0.1, reason: 'x')
      expect(backtester.send(:map_signal, signal, candle)).to be_nil
    end
  end

  describe 'end-to-end backtest' do
    let!(:instrument) { create(:instrument, :nifty_index) }

    def raw_candles_for(from_date:, to_date:, interval_minutes:)
      rows = []
      (from_date..to_date).each do |date|
        next if date.saturday? || date.sunday?

        t = Time.zone.parse("#{date} 09:15:00")
        day_end = Time.zone.parse("#{date} 15:15:00")
        price = 100.0
        while t < day_end
          rows << { open: price, high: price + 1, low: price - 1, close: price + 0.5,
                    volume: 1000, timestamp: t.iso8601 }
          price += 0.1
          t += interval_minutes.minutes
        end
      end
      rows
    end

    before do
      allow_any_instance_of(Instrument).to receive(:intraday_ohlc) do |_instr, interval:, from_date:, to_date:, **|
        raw_candles_for(from_date: Date.parse(from_date), to_date: Date.parse(to_date), interval_minutes: interval.to_i)
      end
    end

    it 'runs entry decisions through the pinned strategy and tags results with its slug/version' do
      result = described_class.call(
        symbol: 'NIFTY', strategy_version: strategy_version, days_back: 7, trading_type: :futures
      )

      summary = result.summary
      expect(summary[:strategy_slug]).to eq('always-buy-call')
      expect(summary[:strategy_version]).to eq(1)
      expect(summary[:total_trades]).to be_a(Integer)
      expect(summary[:total_trades]).to be >= 1

      first_trade = result.trade_log.first
      expect(first_trade[:reason]).to include('always-buy-call@v1')
    end

    it 'produces the same total_trades count across repeated runs with the same input (reproducibility)' do
      first = described_class.call(symbol: 'NIFTY', strategy_version: strategy_version, days_back: 7, trading_type: :futures)
      second = described_class.call(symbol: 'NIFTY', strategy_version: strategy_version, days_back: 7, trading_type: :futures)

      expect(first.summary[:total_trades]).to eq(second.summary[:total_trades])
    end
  end

  describe '.for_sweep' do
    it 'raises NotImplementedError' do
      expect { described_class.for_sweep(symbol: 'NIFTY') }.to raise_error(NotImplementedError)
    end
  end
end
