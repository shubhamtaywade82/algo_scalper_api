# frozen_string_literal: true

require 'rails_helper'

RSpec.describe IndiaIndexRegistry do
  before { described_class.reset! }

  describe '.merge_into' do
    it 'applies canonical identity and execution from registry' do
      merged = described_class.merge_into(
        key: 'SENSEX',
        capital_alloc_pct: 0.30,
        segment: 'WRONG',
        sid: '99'
      )

      expect(merged[:segment]).to eq('IDX_I')
      expect(merged[:sid]).to eq('51')
      expect(merged[:fno_segment]).to eq('BSE_FNO')
      expect(merged[:lot]).to eq(10)
      expect(merged[:execution][:max_bid_ask_spread_pct]).to eq(0.025)
      expect(merged[:execution][:earliest_entry_time]).to eq('09:30')
      expect(merged[:capital_alloc_pct]).to eq(0.30)
    end

    it 'allows algo execution overrides on top of registry defaults' do
      merged = described_class.merge_into(
        key: 'NIFTY',
        execution: { max_bid_ask_spread_pct: 0.02 }
      )

      expect(merged[:execution][:max_bid_ask_spread_pct]).to eq(0.02)
      expect(merged[:execution][:earliest_entry_time]).to eq('09:30')
    end

    it 'returns overlay unchanged when key is unknown' do
      overlay = { key: 'UNKNOWN', segment: 'IDX_I' }
      expect(described_class.merge_into(overlay)).to eq(overlay)
    end
  end

  describe '.merge_indices!' do
    it 'merges each index entry' do
      merged = described_class.merge_indices!([{ key: 'BANKNIFTY', direction: :bullish }])
      entry = merged.first

      expect(entry[:sid]).to eq('25')
      expect(entry[:lot]).to eq(15)
      expect(entry[:direction]).to eq(:bullish)
    end
  end
end
