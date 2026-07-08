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
  end
end
