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

    context 'when new trades are allowed and entries are permitted' do
      before do
        allow(Live::TimeRegimeService.instance).to receive_messages(allow_new_trades?: true, allow_entries?: true, current_regime: :trend_continuation)
      end

      it 'passes' do
        result = described_class.call(context)

        expect(result).to eq(Entries::EntryGuardPipeline::PASS)
      end
    end
  end
end
