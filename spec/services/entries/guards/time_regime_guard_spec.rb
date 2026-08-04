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

  context 'when run_mode is exit_testing' do
    before do
      allow(AlgoConfig).to receive(:run_mode).and_return('exit_testing')
    end

    it 'passes without checking time regime' do
      allow(Live::TimeRegimeService.instance).to receive(:allow_new_trades?)

      result = described_class.call(context)

      expect(result).to eq(Entries::EntryGuardPipeline::PASS)
      expect(Live::TimeRegimeService.instance).not_to have_received(:allow_new_trades?)
    end
  end

  context 'when run_mode is production and time regime rules are enabled' do
    before do
      allow(AlgoConfig).to receive(:run_mode).and_return('production')
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

    context 'when new trades are allowed and entries are permitted' do
      before do
        allow(Live::TimeRegimeService.instance).to receive(:allow_new_trades?).and_return(true)
        allow(Live::TimeRegimeService.instance).to receive(:allow_entries?).and_return(true)
        allow(Live::TimeRegimeService.instance).to receive(:current_regime).and_return(:trend_continuation)
      end

      it 'passes' do
        result = described_class.call(context)

        expect(result).to eq(Entries::EntryGuardPipeline::PASS)
      end
    end
  end
end
