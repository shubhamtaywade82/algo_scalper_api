# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Options::AutoCalibrator do
  def fake_dhan_result(candle_count: 5)
    ts_base = Time.new(2026, 3, 10, 9, 15, 0, '+05:30').to_i
    timestamps = candle_count.times.map { |i| ts_base + (i * 300) }
    data_hash = {
      'timestamp' => timestamps,
      'open' => [100.0] * candle_count,
      'high' => [120.0] * candle_count,
      'low' => [90.0] * candle_count,
      'close' => [105.0] * candle_count,
      'volume' => [1000] * candle_count,
      'oi' => [5000] * candle_count,
      'spot' => [22_000.0] * candle_count,
      'strike' => [22_000.0] * candle_count
    }

    result = double('ExpiredOptionsData', data: { 'ce' => data_hash, 'pe' => data_hash })
  end

  before do
    allow(DhanHQ::Models::ExpiredOptionsData).to receive(:fetch).and_return(fake_dhan_result)
    allow(IndexConfigLoader).to receive(:load_indices).and_return([
      { key: 'NIFTY', segment: 'NSE_FNO', sid: '13' }
    ])
    allow(AlgoConfig).to receive(:fetch).and_return(
      risk: {
        percentage_pnl_exit: { target_pct: 0.01 },
        trailing: { activation_pct: 0.01, drawdown_pct: 0.01 },
        profit_floor: { lock_pct: 0.01, trail_pct: 0.01 },
        institutional_trailing: {
          nifty: {
            trailing_distance: 0.01, early_trigger: 0.01,
            breakeven_trigger: 0.01, activation_trigger: 0.01
          }
        }
      }
    )
  end

  describe '.call' do
    it 'returns a persisted CalibrationRun on success' do
      result = described_class.call(symbol: 'NIFTY', weeks: 4)
      expect(result).to be_a(CalibrationRun)
      expect(result).to be_persisted
      expect(result.symbol).to eq('NIFTY')
    end

    it 'returns nil when DhanHQ returns nil for all strikes' do
      allow(DhanHQ::Models::ExpiredOptionsData).to receive(:fetch).and_return(nil)
      expect(described_class.call(symbol: 'NIFTY', weeks: 4)).to be_nil
    end

    it 'returns nil when IndexConfigLoader cannot find the symbol' do
      allow(IndexConfigLoader).to receive(:load_indices).and_return([])
      expect(described_class.call(symbol: 'NIFTY', weeks: 4)).to be_nil
    end
  end
end
