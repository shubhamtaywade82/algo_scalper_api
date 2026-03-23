# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Entries::Guards::SmcNavigatorGuard do
  let(:instrument) { instance_double(Instrument) }
  let(:series) { build(:candle_series, :five_minute, :with_candles) }
  let(:context) do
    {
      instrument: instrument,
      direction: :bullish,
      index_cfg: { key: 'NIFTY' },
      pick: { symbol: 'X' }
    }
  end

  before do
    allow(instrument).to receive(:candle_series).with(interval: Smc::BiasEngine::LTF_INTERVAL).and_return(series)
  end

  context 'when overlay is disabled' do
    before do
      allow(AlgoConfig).to receive(:fetch).and_return(signals: { enable_smc_navigator_overlay: false })
    end

    it 'passes without evaluating navigator' do
      allow(Smc::Navigator).to receive(:evaluate_entry)

      result = described_class.call(context)

      expect(result).to eq(Entries::EntryGuardPipeline::PASS)
      expect(Smc::Navigator).not_to have_received(:evaluate_entry)
    end
  end

  context 'when overlay is enabled' do
    before do
      allow(AlgoConfig).to receive(:fetch).and_return(
        signals: {
          enable_smc_navigator_overlay: true,
          smc_navigator_min_confidence: 0.6
        }
      )
    end

    it 'blocks when navigator vetoes' do
      veto = Smc::Navigator::EntryResult.new(allow: false, reason: :trend_mismatch, confidence: 0.2, details: {})
      allow(Smc::Navigator).to receive(:evaluate_entry).and_return(veto)

      result = described_class.call(context)

      expect(result).to eq({ blocked: 'smc_navigator:trend_mismatch' })
    end

    it 'blocks when confidence is below minimum' do
      low = Smc::Navigator::EntryResult.new(allow: true, reason: :ok, confidence: 0.4, details: {})
      allow(Smc::Navigator).to receive(:evaluate_entry).and_return(low)

      result = described_class.call(context)

      expect(result).to eq({ blocked: 'smc_navigator:low_confidence' })
    end

    it 'passes when navigator allows and confidence is sufficient' do
      ok = Smc::Navigator::EntryResult.new(allow: true, reason: :ok, confidence: 0.85, details: {})
      allow(Smc::Navigator).to receive(:evaluate_entry).and_return(ok)

      result = described_class.call(context)

      expect(result).to eq(Entries::EntryGuardPipeline::PASS)
    end
  end
end
