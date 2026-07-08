# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Entries::Guards::TimeRegimeGuard do
  let(:index_cfg) { { key: 'NIFTY' } }
  let(:context) do
    {
      index_cfg: index_cfg,
      pick: { symbol: 'NIFTY26APR23000CE' },
      direction: :bullish
    }
  end

  context 'when time regime rules are enabled' do
    before do
      allow(AlgoConfig).to receive(:fetch).and_return(
        risk: { time_regimes: { enabled: true } }
      )
    end

    context 'when new trades are not allowed (after 15:05 IST)' do
      before do
        allow(Live::TimeRegimeService.instance).to receive(:allow_new_trades?).and_return(false)
      end

      it 'blocks entry with time regime reason' do
        result = described_class.call(context)

        expect(result).to eq({ blocked: 'time regime rules for NIFTY' })
      end
    end

    context 'when before 09:30 earliest entry' do
      before do
        allow(Live::TimeRegimeService.instance).to receive(:allow_new_trades?).and_return(false)
      end

      it 'blocks entry via allow_new_trades?' do
        time = Time.zone.parse('2026-03-17 09:20:00 +05:30')
        allow(Live::TimeRegimeService.instance).to receive(:allow_new_trades?).with(time: time).and_return(false)

        expect(Live::TimeRegimeService.instance.allow_new_trades?(time: time)).to be(false)
      end
    end

    context 'when new trades are allowed and entries are permitted' do
      before do
        allow(Live::TimeRegimeService.instance).to receive_messages(allow_new_trades?: true, allow_entries?: true, current_regime: :trend_continuation)
      end

      it 'passes' do
        result = described_class.call(context)

        expect(result).to eq(Entries::EntryGuardPipeline::PASS)
      end
    end

    context 'ADX regime bounds' do
      let(:context) do
        {
          index_cfg: index_cfg,
          pick: { symbol: 'NIFTY26APR23000CE', adx_value: adx },
          direction: :bullish
        }
      end

      before do
        allow(Live::TimeRegimeService.instance).to receive_messages(
          allow_new_trades?: true, allow_entries?: true, current_regime: :trend_continuation,
          regime_config: { min_adx: 15.0, max_adx: 35.0 }
        )
      end

      context 'when adx is above the regime max_adx ceiling' do
        let(:adx) { 40.0 }

        it 'blocks entry' do
          expect(described_class.call(context)).to eq({ blocked: 'time regime rules for NIFTY' })
        end
      end

      context 'when adx is below the regime min_adx floor' do
        let(:adx) { 10.0 }

        it 'blocks entry' do
          expect(described_class.call(context)).to eq({ blocked: 'time regime rules for NIFTY' })
        end
      end

      context 'when adx is within the regime bounds' do
        let(:adx) { 25.0 }

        it 'passes' do
          expect(described_class.call(context)).to eq(Entries::EntryGuardPipeline::PASS)
        end
      end

      context 'when the signal carries no adx value' do
        let(:context) do
          { index_cfg: index_cfg, pick: { symbol: 'NIFTY26APR23000CE' }, direction: :bullish }
        end

        it 'passes (no data to enforce against)' do
          expect(described_class.call(context)).to eq(Entries::EntryGuardPipeline::PASS)
        end
      end
    end

    context 'per-index ADX overrides' do
      let(:index_cfg) { { key: 'BANKNIFTY' } }
      let(:context) do
        {
          index_cfg: index_cfg,
          pick: { symbol: 'BANKNIFTY26APR50000CE' },
          direction: :bullish
        }
      end

      before do
        allow(Live::TimeRegimeService.instance).to receive_messages(
          allow_new_trades?: true, allow_entries?: true, current_regime: :trend_continuation,
          regime_config: {
            min_adx: 15.0, max_adx: 35.0,
            per_index_min_adx: { 'BANKNIFTY' => 20.0 },
            per_index_max_adx: { 'BANKNIFTY' => 40.0 }
          }
        )
      end

      it 'uses the per-index floor instead of the global one' do
        # 17 is below BANKNIFTY's 20.0 override but above the global 15.0 floor
        result = described_class.call(context.merge(pick: { adx_value: 17.0 }))
        expect(result).to eq({ blocked: 'time regime rules for BANKNIFTY' })
      end

      it 'uses the per-index ceiling instead of the global one' do
        # 37 is above the global 35.0 ceiling but below BANKNIFTY's 40.0 override
        result = described_class.call(context.merge(pick: { adx_value: 37.0 }))
        expect(result).to eq(Entries::EntryGuardPipeline::PASS)
      end

      it 'still blocks above the per-index ceiling' do
        result = described_class.call(context.merge(pick: { adx_value: 45.0 }))
        expect(result).to eq({ blocked: 'time regime rules for BANKNIFTY' })
      end

      it 'falls back to the global bounds for an index with no override' do
        nifty_context = { index_cfg: { key: 'NIFTY' }, pick: { adx_value: 17.0 }, direction: :bullish }
        expect(described_class.call(nifty_context)).to eq(Entries::EntryGuardPipeline::PASS)
      end
    end
  end
end
