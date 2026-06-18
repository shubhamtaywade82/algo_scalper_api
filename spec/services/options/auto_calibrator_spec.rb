# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Options::AutoCalibrator do
  let(:symbol) { 'NIFTY' }

  # Minimal fake ExpiredOptionsData response
  def fake_dhan_result(candle_count: 5)
    ts_base = Time.new(2026, 3, 10, 9, 15, 0, '+05:30').to_i
    timestamps = Array.new(candle_count) { |i| ts_base + (i * 300) } # 5-min bars

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

    # Use plain double: DhanHQ assigns :data via define_singleton_method, not class-level,
    # so instance_double cannot verify the interface.
    result = double('DhanHQ::Models::ExpiredOptionsData') # rubocop:disable RSpec/VerifiedDoubles
    allow(result).to receive(:data).and_return({ 'ce' => data_hash, 'pe' => data_hash })
    result
  end

  before do
    # Stub all DhanHQ fetches to return fake data
    allow(DhanHQ::Models::ExpiredOptionsData).to receive(:fetch).and_return(fake_dhan_result)

    # Stub IndexConfigLoader
    allow(IndexConfigLoader).to receive(:load_indices).and_return([
                                                                    { key: 'NIFTY', segment: 'IDX_I', sid: '13' }
                                                                  ])

    # Self-contained: do not depend on Derivative rows for weekly NIFTY expiries
    fake_expiries = Array.new(8) { |i| Date.current - (i * 7) }
    # rubocop:disable RSpec/AnyInstance -- isolates spec from derivative fixture drift
    allow_any_instance_of(described_class).to receive(:historical_weekly_expiry_dates).and_return(fake_expiries)
    # rubocop:enable RSpec/AnyInstance
  end

  describe '.call' do
    it 'returns a CalibrationRun record on success' do
      result = described_class.call(symbol: 'NIFTY', weeks: 4)
      expect(result).to be_a(CalibrationRun)
      expect(result).to be_persisted
    end

    it 'persists the CalibrationRun with the correct symbol' do
      described_class.call(symbol: 'NIFTY', weeks: 4)
      run = CalibrationRun.last
      expect(run.symbol).to eq('NIFTY')
    end

    it 'stores non-empty raw_stats' do
      described_class.call(symbol: 'NIFTY', weeks: 4)
      run = CalibrationRun.last
      expect(run.raw_stats).not_to be_empty
      expect(run.raw_stats['weeks_available'].to_i).to eq(8)
    end

    it 'stores proposed_patch (may be empty hash if nothing changed >10%)' do
      described_class.call(symbol: 'NIFTY', weeks: 4)
      run = CalibrationRun.last
      expect(run.proposed_patch).to be_a(Hash)
    end

    it 'returns nil when DhanHQ returns nil for all strikes' do
      allow(DhanHQ::Models::ExpiredOptionsData).to receive(:fetch).and_return(nil)
      result = described_class.call(symbol: 'NIFTY', weeks: 4)
      expect(result).to be_nil
    end

    it 'returns nil when IndexConfigLoader cannot find the symbol' do
      allow(IndexConfigLoader).to receive(:load_indices).and_return([])
      result = described_class.call(symbol: 'NIFTY', weeks: 4)
      expect(result).to be_nil
    end

    it 'still returns a result when only the first ATM fetch succeeds (all other fetches fail)' do
      call_count = 0
      allow(DhanHQ::Models::ExpiredOptionsData).to receive(:fetch) do
        call_count += 1
        call_count == 1 ? fake_dhan_result : nil # ATM succeeds, rest fail
      end
      result = described_class.call(symbol: 'NIFTY', weeks: 4)
      expect(result).not_to be_nil
    end
  end
end
