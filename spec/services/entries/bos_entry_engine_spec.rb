# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Entries::BosEntryEngine do
  let(:index_cfg) { { key: 'NIFTY', segment: 'NSE_FNO' } }
  let(:candles) do
    [
      build_candle(105, 110, 100),
      build_candle(115, 120, 110),
      build_candle(125, 130, 120)
    ]
  end
  let(:series) { double('CandleSeries', candles: candles, timeframe: '5m') }
  let(:instrument) { instance_double(Instrument, symbol_name: 'NIFTY') }
  let(:direction) { :bullish }
  let(:picks) { [{ symbol: 'NIFTY24MAR22000CE', security_id: '12345' }] }
  let(:entry_metadata) { { effective_timeframe: '5m' } }
  let(:permission) { :scale_ready }
  let(:signal) { double('Signal', record_entry_outcome: true) }

  # Mock Candles
  def build_candle(close, high, low, open = 100, timestamp = Time.current)
    double('Candle', close: close, high: high, low: low, open: open, timestamp: timestamp)
  end

  before do
    # Use MemoryStore for cache during tests since test environment uses NullStore
    allow(Rails).to receive(:cache).and_return(ActiveSupport::Cache::MemoryStore.new)
    allow(instrument).to receive(:candle_series).and_return(series)
    Rails.cache.clear
  end

  describe '.run_for' do
    context 'when no BOS is found' do
      before do
        allow(Entries::BosExtractor).to receive(:last_confirmed_bos).and_return(nil)
      end

      it 'returns false and resets state' do
        expect(described_class.run_for(
          index_cfg: index_cfg, instrument: instrument, direction: direction,
          picks: picks, entry_metadata: entry_metadata, permission: permission
        )).to be false
      end
    end

    context 'when a new BOS is confirmed' do
      let(:bos) do
        {
          direction: :bullish,
          confirmed_at: Time.current,
          confirmed_index: 2,
          broken_swing: { price: 120 },
          origin_swing: { price: 100 }
        }
      end

      before do
        allow(Entries::BosExtractor).to receive_messages(last_confirmed_bos: bos, bos_id: 'bos_123')
      end

      it 'initializes state to bos_confirmed and returns false' do
        expect(described_class.run_for(
          index_cfg: index_cfg, instrument: instrument, direction: direction,
          picks: picks, entry_metadata: entry_metadata, permission: permission
        )).to be false

        state = Rails.cache.read("bos_machine:NIFTY:5m")
        expect(state).not_to be_nil
        expect(state[:state]).to eq('bos_confirmed')
        expect(state[:bos_id]).to eq('bos_123')
      end
    end

    context 'when in bos_confirmed state and pullback occurs' do
      let(:state) do
        {
          state: 'bos_confirmed',
          bos_id: 'bos_123',
          direction: :bullish,
          bos_level: 120,
          origin_price: 100,
          confirmed_index: 2,
          confirmed_at: 5.minutes.ago
        }
      end

      # Pullback detection logic: retrace_pct >= 0.35 && opposite_close
      # retrace_pct = (bos_level - lowest_low) / (bos_level - origin_price)
      # bos_level=120, origin=100. Leg=20.
      # retrace = 120 - 110 = 10. 10/20 = 0.5.
      let(:pullback_candles) do
        candles + [
          build_candle(115, 126, 114), # Opposite close (115 < 125)
          build_candle(110, 115, 110)  # Retrace to 110 (result 0.5)
        ]
      end

      before do
        Rails.cache.write("bos_machine:NIFTY:5m", state)
        allow(series).to receive(:candles).and_return(pullback_candles)
        allow(Entries::BosExtractor).to receive_messages(last_confirmed_bos: { direction: :bullish, confirmed_at: state[:confirmed_at], confirmed_index: 2 }, bos_id: 'bos_123')
      end

      it 'transitions to pullback state' do
        described_class.run_for(
          index_cfg: index_cfg, instrument: instrument, direction: direction,
          picks: picks, entry_metadata: entry_metadata, permission: permission
        )

        new_state = Rails.cache.read("bos_machine:NIFTY:5m")
        expect(new_state).not_to be_nil
        expect(new_state[:state]).to eq('pullback')
        expect(new_state[:pullback_retrace_pct]).to be >= 0.35
      end
    end

    context 'when in pullback state and continuation occurs' do
      let(:state) do
        {
          state: 'pullback',
          bos_id: 'bos_123',
          direction: :bullish,
          bos_level: 120,
          origin_price: 100,
          confirmed_index: 2,
          pullback_started_at_index: 4,
          pullback_high: 110,
          pullback_retrace_pct: 0.5
        }
      end

      # continuation_triggered? for bullish: close > pullback_level && body_position >= 0.6
      # body_pos = (close - low) / (high - low)
      # 125 close, 110 low, 130 high -> (125-110)/(130-110) = 15/20 = 0.75
      let(:continuation_candles) do
        candles + [
          build_candle(115, 120, 110),
          build_candle(125, 130, 110)
        ]
      end

      before do
        Rails.cache.write("bos_machine:NIFTY:5m", state)
        allow(series).to receive(:candles).and_return(continuation_candles)
        allow(Entries::BosExtractor).to receive_messages(last_confirmed_bos: { direction: :bullish, confirmed_at: Time.current, confirmed_index: 2 }, bos_id: 'bos_123')
        allow(Entries::EntryGuard).to receive(:try_enter).and_return(true)
        allow(described_class).to receive(:htf_bias_allows?).and_return(true)
      end

      it 'triggers entry and resets state' do
        result = described_class.run_for(
          index_cfg: index_cfg, instrument: instrument, direction: direction,
          picks: picks, entry_metadata: entry_metadata, permission: permission
        )

        expect(result).to be true
        expect(Entries::EntryGuard).to have_received(:try_enter)
        expect(Rails.cache.read("bos_machine:NIFTY:5m")).to be_nil
      end
    end
  end
end
