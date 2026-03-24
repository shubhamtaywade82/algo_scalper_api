# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Smc::Navigator do
  describe '.evaluate_entry' do
    let(:instrument) { instance_double(Instrument) }
    let(:series) { build(:candle_series, :five_minute, :with_candles) }

    before do
      allow(instrument).to receive(:candle_series).with(interval: Smc::BiasEngine::LTF_INTERVAL).and_return(series)
    end

    context 'when candle history is too short' do
      let(:series) { build(:candle_series, :five_minute) }

      it 'fail-opens with high confidence' do
        result = described_class.evaluate_entry(price: nil, direction: :bullish, instrument: instrument)

        expect(result.allow?).to be true
        expect(result.reason).to eq(:insufficient_smc_data)
        expect(result.confidence).to eq(1.0)
      end
    end

    context 'when trend opposes direction' do
      let(:pd) do
        instance_double(Smc::Detectors::PremiumDiscount, to_h: { discount: true, premium: false })
      end
      let(:liquidity) do
        instance_double(Smc::Detectors::Liquidity, to_h: { buy_side_taken: false, sell_side_taken: false })
      end
      let(:swing) { instance_double(Smc::Detectors::SwingStructure) }
      let(:ctx) do
        instance_double(
          Smc::Context,
          trend: :bearish,
          phase: :neutral,
          liquidity: liquidity,
          pd: pd
        )
      end

      before do
        allow(Smc::Context).to receive(:new).with(series).and_return(ctx)
      end

      it 'vetoes bullish entries' do
        result = described_class.evaluate_entry(price: nil, direction: :bullish, instrument: instrument)

        expect(result.allow?).to be false
        expect(result.reason).to eq(:trend_mismatch)
      end
    end
  end

  describe '.evaluate_exit' do
    let(:instrument) { instance_double(Instrument) }
    let(:tracker) { build_stubbed(:position_tracker, symbol: 'NIFTY24JAN25000CE') }
    let(:series) { build(:candle_series, :five_minute, :with_candles) }

    before do
      allow(instrument).to receive(:candle_series).with(interval: Smc::BiasEngine::LTF_INTERVAL).and_return(series)
    end

    context 'when structure opposes long CE' do
      let(:pd) do
        instance_double(Smc::Detectors::PremiumDiscount, to_h: { discount: false, premium: true })
      end
      let(:liquidity) do
        instance_double(Smc::Detectors::Liquidity, to_h: { buy_side_taken: false, sell_side_taken: false })
      end
      let(:ctx) do
        instance_double(
          Smc::Context,
          trend: :bearish,
          phase: :neutral,
          liquidity: liquidity,
          pd: pd
        )
      end

      before do
        allow(Smc::Context).to receive(:new).with(series).and_return(ctx)
      end

      it 'suggests exit' do
        result = described_class.evaluate_exit(tracker: tracker, ltp: 100.0, instrument: instrument)

        expect(result.suggest_exit?).to be true
        expect(result.reason).to eq(:structure_bearish)
      end
    end
  end

  describe '.log_exit_advisory' do
    let(:instrument) { instance_double(Instrument) }
    let(:tracker) { build_stubbed(:position_tracker, symbol: 'NIFTY24JAN25000CE') }
    let(:exit_result) do
      described_class::ExitResult.new(
        suggest_exit: true,
        reason: :structure_bearish,
        confidence: 0.7,
        details: {}
      )
    end

    it 'logs when advisory is enabled and exit is suggested' do
      allow(AlgoConfig).to receive(:fetch).and_return(
        signals: { smc_navigator_exit_advisory: true }
      )
      allow(described_class).to receive(:evaluate_exit).and_return(exit_result)
      allow(Observability::StructuredLog).to receive(:info)

      described_class.log_exit_advisory(tracker: tracker, ltp: 50.0, instrument: instrument)

      expect(Observability::StructuredLog).to have_received(:info).with(
        hash_including(event: 'smc_exit_advisory')
      )
    end

    it 'does nothing when advisory is disabled' do
      allow(AlgoConfig).to receive(:fetch).and_return(
        signals: { smc_navigator_exit_advisory: false }
      )
      allow(Observability::StructuredLog).to receive(:info)

      described_class.log_exit_advisory(tracker: tracker, ltp: 50.0, instrument: instrument)

      expect(Observability::StructuredLog).not_to have_received(:info)
    end
  end
end
