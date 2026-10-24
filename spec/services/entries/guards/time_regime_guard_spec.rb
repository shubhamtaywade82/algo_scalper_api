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
      allow(AlgoConfig).to receive_messages(run_mode: 'production', fetch: { risk: { time_regimes: { enabled: true } } })
    end

    context 'when new trades are not allowed (after 15:05 IST)' do
      before do
        allow(Live::TimeRegimeService.instance).to receive_messages(
          current_regime: :trend_continuation,
          allow_new_trades?: false
        )
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

    context 'when regime resolution fails (corrupt config / coverage gap)' do
      before do
        allow(Live::TimeRegimeService.instance).to receive(:current_regime)
          .and_raise(Errors::ConfigurationError, 'risk.time_regimes is enabled but no regime window covers 12:00 IST')
      end

      it 'blocks (fail-closed) instead of passing' do
        result = described_class.call(context)

        expect(result).to eq({ blocked: 'time regime rules for NIFTY' })
      end
    end

    context 'when the check itself crashes with an unexpected error' do
      before do
        allow(Live::TimeRegimeService.instance).to receive(:current_regime).and_raise(NoMethodError, 'undefined method')
      end

      it 'blocks instead of assuming entries are allowed' do
        result = described_class.call(context)

        expect(result).to eq({ blocked: 'time regime rules for NIFTY' })
      end
    end
  end

  context 'when time regime rules are disabled' do
    before do
      allow(AlgoConfig).to receive_messages(run_mode: 'production', fetch: { risk: { time_regimes: { enabled: false } } })
      allow(Live::TimeRegimeService.instance).to receive(:current_regime)
    end

    it 'passes without consulting the regime service' do
      result = described_class.call(context)

      expect(result).to eq(Entries::EntryGuardPipeline::PASS)
      expect(Live::TimeRegimeService.instance).not_to have_received(:current_regime)
    end
  end
end
