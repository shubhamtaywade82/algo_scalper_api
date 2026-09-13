# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Backtest::OptionTradeSimulator do
  let(:instrument) { create(:instrument, :nifty_index, symbol_name: 'NIFTY') }
  let(:simulator) { described_class.new(instrument: instrument) }

  # Helpers to build fake option data with multiple strikes (rolling ATM simulation)
  def build_rolling_option_bars(base_time:, strikes:, bar_interval: 1.minute)
    bars = []
    # Each bar gets the "ATM" strike that would be resolved at that moment.
    # As spot drifts, the ATM strike flips between adjacent strikes.
    strikes.each_with_index do |strike_data, i|
      ts = base_time + (i * bar_interval)
      bars << {
        timestamp: ts,
        open: strike_data[:price] - 2,
        high: strike_data[:price] + 5,
        low: strike_data[:price] - 5,
        close: strike_data[:price],
        volume: 10_000,
        strike: strike_data[:strike].to_s
      }
    end
    bars
  end

  describe '#enter_position' do
    let(:candle) do
      Candle.new(
        timestamp: Time.zone.parse('2026-07-06 10:00:00'),
        open: 25_000, high: 25_050, low: 24_950, close: 25_025, volume: 500
      )
    end

    context 'when option data is available' do
      before do
        option_data = [
          { timestamp: candle.timestamp - 30.seconds, close: 200.0, strike: '24500' },
          { timestamp: candle.timestamp, close: 210.0, strike: '24500' },
          { timestamp: candle.timestamp + 30.seconds, close: 215.0, strike: '24600' } # different strike
        ]
        allow(Options::ExpiredFetcher).to receive(:call).and_return({ ce: option_data, pe: [] })
      end

      it 'stores entry_strike from the matched bar' do
        position = simulator.enter_position({ type: :ce }, candle, 0)
        expect(position).not_to be_nil
        expect(position[:entry_strike]).to eq('24500')
        expect(position[:entry_price]).to eq(210.0)
      end

      it 'stores the full option_data for later same-strike filtering' do
        position = simulator.enter_position({ type: :ce }, candle, 0)
        expect(position[:option_data].size).to eq(3)
      end
    end

    context 'when option data is blank' do
      before do
        allow(Options::ExpiredFetcher).to receive(:call).and_return({ ce: [], pe: [] })
      end

      it 'returns nil' do
        position = simulator.enter_position({ type: :ce }, candle, 0)
        expect(position).to be_nil
      end
    end
  end

  describe '#check_exit (same-strike filtering)' do
    let(:base_time) { Time.zone.parse('2026-07-06 10:00:00') }
    let(:candle_entry) do
      Candle.new(timestamp: base_time, open: 25_000, high: 25_050, low: 24_950, close: 25_025, volume: 500)
    end

    # Simulate rolling ATM: strike flips between 24500 and 24600 as spot drifts
    let(:option_data) do
      [
        { timestamp: base_time,             close: 210.0, strike: '24500' },
        { timestamp: base_time + 1.minute,  close: 220.0, strike: '24500' },
        { timestamp: base_time + 2.minutes, close: 100.0, strike: '24600' }, # different strike (cheap)
        { timestamp: base_time + 3.minutes, close: 90.0,  strike: '24600' }, # different strike
        { timestamp: base_time + 4.minutes, close: 240.0, strike: '24500' }, # back to entry strike
        { timestamp: base_time + 5.minutes, close: 250.0, strike: '24500' } # entry strike hits target
      ]
    end

    let(:position) do
      {
        signal_type: :ce,
        entry_index: 0,
        entry_time: base_time,
        entry_price: 210.0,
        entry_strike: '24500',
        option_data: option_data,
        stop_loss: 210.0 * 0.70, # 147
        target: 210.0 * 1.50 # 315
      }
    end

    before do
      # The simulator fetches data via Options::ExpiredFetcher for enter_position,
      # but check_exit uses the already-stored option_data, filtering by strike.
      allow(Options::ExpiredFetcher).to receive(:call).and_return({ ce: option_data, pe: [] })
    end

    it 'only considers bars matching the entry strike' do
      # At base_time + 2 min, the rolling ATM flipped to 24600.
      # The simulator should SKIP this bar (different strike) rather than
      # seeing a fake drop to 100.
      check_candle = Candle.new(
        timestamp: base_time + 2.minutes,
        open: 25_100, high: 25_150, low: 25_050, close: 25_100, volume: 500
      )
      result = simulator.check_exit(position, check_candle, 2, nil)
      # The 24600 bar at close=100 is skipped, so no exit triggered
      # (nearest same-strike bar is still around 220)
      expect(result).to be_nil
    end

    it 'detects target hit on a same-strike bar' do
      # At base_time + 5 min, strike 24500 has close=250, which hits target of 315?
      # Actually 250 < 315 (target), so let's adjust... The target is entry * 1.5 = 315.
      # Let me use a higher price for the target-hit bar.
      option_data_target = option_data.dup
      option_data_target[5] = { timestamp: base_time + 5.minutes, close: 320.0, strike: '24500' }
      position_target = position.merge(option_data: option_data_target)

      check_candle = Candle.new(
        timestamp: base_time + 5.minutes,
        open: 25_300, high: 25_350, low: 25_250, close: 25_300, volume: 500
      )
      result = simulator.check_exit(position_target, check_candle, 5, nil)
      expect(result).not_to be_nil
      expect(result[:exit_reason]).to eq('target')
      expect(result[:exit_price]).to eq(320.0)
    end

    it 'returns nil when no same-strike bar exists near the timestamp' do
      # Check at a time when only 24600 bars exist
      check_candle = Candle.new(
        timestamp: base_time + 3.minutes,
        open: 25_080, high: 25_130, low: 25_030, close: 25_080, volume: 500
      )
      result = simulator.check_exit(position, check_candle, 3, nil)
      # No same-strike bar at this time → returns nil
      expect(result).to be_nil
    end
  end

  describe '#force_exit with same-strike filtering' do
    let(:base_time) { Time.zone.parse('2026-07-06 10:00:00') }
    let(:option_data) do
      [
        { timestamp: base_time,             close: 200.0, strike: '24500' },
        { timestamp: base_time + 5.minutes, close: 100.0, strike: '24600' } # different strike
      ]
    end
    let(:position) do
      {
        signal_type: :ce,
        entry_index: 0,
        entry_time: base_time,
        entry_price: 200.0,
        entry_strike: '24500',
        option_data: option_data,
        stop_loss: 140.0,
        target: 300.0
      }
    end

    it 'falls back to 50% of entry when no same-strike bar is available' do
      last_candle = Candle.new(
        timestamp: base_time + 5.minutes,
        open: 25_100, high: 25_150, low: 25_050, close: 25_100, volume: 500
      )
      result = simulator.force_exit(position, last_candle, 5, 'end_of_data')
      expect(result[:exit_reason]).to eq('end_of_data')
      # Falls back to entry_price * 0.5 = 100
      expect(result[:exit_price]).to eq(100.0)
    end
  end

  describe '#simulate_trade (end-to-end with rolling strikes)' do
    let(:base_time) { Time.zone.parse('2026-07-06 09:30:00') }

    let(:option_data_ce) do
      bars = []
      (0..10).each do |i|
        # Strike flips every 3 bars to simulate rolling ATM
        strike = i.even? ? '24500' : '24600'
        price = 200.0 + (i * 10.0) # monotonic rise for CE
        bars << { timestamp: base_time + i.minutes, close: price, strike: strike }
      end
      bars
    end

    let(:series) do
      s = CandleSeries.new(symbol: 'NIFTY', interval: '1')
      (0..10).each do |i|
        s.add_candle(Candle.new(
          timestamp: base_time + i.minutes,
          open: 25_000 + (i * 5), high: 25_020 + (i * 5),
          low: 24_980 + (i * 5), close: 25_010 + (i * 5), volume: 500
        ))
      end
      s
    end

    before do
      allow(Options::ExpiredFetcher).to receive(:call).and_return({ ce: option_data_ce, pe: [] })
    end

    it 'runs a full trade using only same-strike bars' do
      result = simulator.simulate_trade(series: series, entry_index: 0, signal_type: :ce)
      expect(result).not_to be_nil
      expect(result[:signal_type]).to eq(:ce)
      # The entry is at strike 24500, price 200
      expect(result[:entry_price]).to eq(200.0)
      # Should only consider even-indexed bars (strike 24500)
      expect(result[:entry_time]).to eq(base_time)
    end
  end
end
