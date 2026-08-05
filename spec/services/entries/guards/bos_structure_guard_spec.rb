# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Entries::Guards::BosStructureGuard do
  describe '.call' do
    let(:context) do
      {
        index_cfg: { key: 'NIFTY' },
        instrument: instrument,
        direction: direction,
        ltp: 22_500,
        entry_metadata: entry_metadata
      }
    end
    let(:instrument) { create(:instrument, :nifty_index) }
    let(:direction) { :bullish }
    let(:entry_metadata) { { primary_timeframe: '5m', effective_timeframe: '5m' } }
    let(:candle_series) { instance_double(Live::CandleSeriesCache) }
    let(:candles) { [] }
    let(:bos_extractor) { class_double(Entries::BosExtractor) }

    before do
      allow(instrument).to receive(:candle_series).with(interval: '5m').and_return(candle_series)
      allow(candle_series).to receive(:candles).and_return(candles)
      allow(Entries::BosExtractor).to receive(:last_confirmed_bos).and_return(nil)
      allow(Entries::BosExtractor).to receive(:bos_id).and_return('bos_123')
      allow(Rails.cache).to receive(:read).and_return(false)
    end

    context 'when in supertrend mode' do
      let(:entry_metadata) { { entry_contract: 'supertrend_machine_v1' } }

      it 'allows entry without checking BOS structure' do
        result = described_class.call(context)
        expect(result).to eq(Entries::EntryGuardPipeline::PASS)
      end
    end

    context 'when not in supertrend mode' do
      context 'and no candles are available' do
        let(:candles) { [] }

        it 'blocks entry' do
          result = described_class.call(context)
          expect(result).to eq(blocked: 'bos_structure_gate')
        end
      end

      context 'and BOS is not found' do
        let(:candles) { [instance_double(Candle)] }

        before do
          allow(Entries::BosExtractor).to receive(:last_confirmed_bos).and_return(nil)
        end

        it 'blocks entry' do
          result = described_class.call(context)
          expect(result).to eq(blocked: 'bos_structure_gate')
        end
      end

      context 'and BOS direction does not match' do
        let(:candles) { [instance_double(Candle)] }
        let(:bos) { { direction: :bearish, confirmed_index: 0, origin_swing: { price: 22_400 }, broken_swing: { price: 22_450 }, confirmed_at: Time.current } }

        before do
          allow(Entries::BosExtractor).to receive(:last_confirmed_bos).and_return(bos)
        end

        it 'blocks entry' do
          result = described_class.call(context)
          expect(result).to eq(blocked: 'bos_structure_gate')
        end
      end

      context 'and BOS is too old' do
        let(:candles) { Array.new(10) { |i| instance_double(Candle, close: 22_500 + i) } }
        let(:bos) { { direction: :bullish, confirmed_index: 0, origin_swing: { price: 22_400 }, broken_swing: { price: 22_450 }, confirmed_at: Time.current } }

        before do
          allow(Entries::BosExtractor).to receive(:last_confirmed_bos).and_return(bos)
        end

        it 'blocks entry' do
          result = described_class.call(context)
          expect(result).to eq(blocked: 'bos_structure_gate')
        end
      end

      context 'and entry distance is too far' do
        let(:candles) { Array.new(5) { |i| instance_double(Candle, close: 22_500 + (i * 100)) } }
        let(:bos) { { direction: :bullish, confirmed_index: 3, origin_swing: { price: 22_400 }, broken_swing: { price: 22_450 }, confirmed_at: Time.current } }

        before do
          allow(Entries::BosExtractor).to receive(:last_confirmed_bos).and_return(bos)
        end

        it 'blocks entry' do
          result = described_class.call(context)
          expect(result).to eq(blocked: 'bos_structure_gate')
        end
      end

      context 'and BOS has already been consumed' do
        let(:candles) { Array.new(5) { |i| instance_double(Candle, close: 22_450 + (i * 10)) } }
        let(:bos) { { direction: :bullish, confirmed_index: 3, origin_swing: { price: 22_400 }, broken_swing: { price: 22_450 }, confirmed_at: Time.current } }

        before do
          allow(Entries::BosExtractor).to receive(:last_confirmed_bos).and_return(bos)
          allow(Entries::BosExtractor).to receive(:bos_id).and_return('bos_123')
          allow(Rails.cache).to receive(:read).with("bos:consumed:NIFTY:bos_123").and_return(true)
        end

        it 'blocks entry' do
          result = described_class.call(context)
          expect(result).to eq(blocked: 'bos_structure_gate')
        end
      end

      context 'and all conditions are met' do
        let(:candles) { Array.new(5) { |i| instance_double(Candle, close: 22_450 + (i * 5)) } }
        let(:bos) { { direction: :bullish, confirmed_index: 3, origin_swing: { price: 22_400 }, broken_swing: { price: 22_450 }, confirmed_at: Time.current } }
        let(:expected_bos_context) do
          bos.merge(
            timeframe: '5m',
            bos_id: 'bos_123',
            entry_distance_r: kind_of(Numeric),
            risk_points: 50.0,
            entry_underlying_price: 22_470
          )
        end

        before do
          allow(Entries::BosExtractor).to receive(:last_confirmed_bos).and_return(bos)
          allow(Entries::BosExtractor).to receive(:bos_id).and_return('bos_123')
          allow(Rails.cache).to receive(:read).and_return(false)
        end

        it 'allows entry and sets bos_context in context' do
          result = described_class.call(context)
          expect(result).to eq(Entries::EntryGuardPipeline::PASS)
          expect(context[:bos_context]).to include(direction: :bullish, timeframe: '5m')
        end
      end
    end
  end
end
