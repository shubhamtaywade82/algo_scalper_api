# frozen_string_literal: true

require 'rails_helper'

RSpec.describe OptionsBuying::TradeScoringEngine do
  let(:index_key) { 'NIFTY' }
  let(:direction) { :bullish }
  let(:option_security_id) { '12345' }
  let(:strategy_name) { 'orb_breakout' }
  let(:spot_ltp) { 22_000.0 }

  let(:index_cfg) { { key: 'NIFTY', sid: '26000', segment: 'NSE_IDX' } }
  let(:instrument) { instance_double(Instrument) }

  before do
    allow(IndexConfigLoader).to receive(:load_indices).and_return([index_cfg])
    allow(IndexInstrumentCache.instance).to receive(:get_or_fetch).with(index_cfg).and_return(instrument)

    # Stub instrument indicators
    allow(instrument).to receive(:candle_series).with(interval: '5').and_return(nil)
    allow(instrument).to receive(:adx).with(14, interval: '5').and_return(25.0)
    allow(instrument).to receive(:rsi).with(14, interval: '5').and_return(55.0)

    # Stub Redis/StateStore metrics
    allow(OptionsBuying::StateStore).to receive(:cache_snapshot).with(option_security_id).and_return({ bid: 100.0, ask: 100.2 })
    allow(OptionsBuying::StateStore).to receive(:volume_rate_baseline).with(option_security_id).and_return(200.0)
    allow(OptionsBuying::StateStore).to receive(:stream_window).with(option_security_id).and_return([])
    allow(OptionsBuying::StateStore).to receive(:volume_threshold_baseline).with(option_security_id).and_return(100.0)

    # Stub Gamma Wall Detector
    gamma_detector = instance_double(OptionsBuying::GammaWallDetector, safe_to_enter?: true)
    allow(OptionsBuying::GammaWallDetector).to receive(:new).with(index_key).and_return(gamma_detector)

    # Disable config merge error
    allow(OptionsBuying::Mode).to receive(:config).and_return({ scoring: { threshold: 60.0 } })
  end

  describe '.score!' do
    it 'calculates a composite score and passes if above the threshold' do
      result = described_class.score!(
        index_key: index_key,
        direction: direction,
        option_security_id: option_security_id,
        strategy_name: strategy_name,
        spot_ltp: spot_ltp
      )

      expect(result[:passed]).to be(true)
      expect(result[:score]).to be >= 60.0
      expect(result[:breakdown]).to include(
        :context_score,
        :momentum_score,
        :liquidity_score,
        :greeks_score,
        :total_score,
        :threshold,
        :passed
      )
    end

    it 'fails the threshold if scores are too low' do
      # Set high threshold
      allow(OptionsBuying::Mode).to receive(:config).and_return({ scoring: { threshold: 95.0 } })

      result = described_class.score!(
        index_key: index_key,
        direction: direction,
        option_security_id: option_security_id,
        strategy_name: strategy_name,
        spot_ltp: spot_ltp
      )

      expect(result[:passed]).to be(false)
    end

    it 'persists a OptionsBuyingSignalEvent' do
      expect do
        described_class.score!(
          index_key: index_key,
          direction: direction,
          option_security_id: option_security_id,
          strategy_name: strategy_name,
          spot_ltp: spot_ltp
        )
      end.to change(OptionsBuyingSignalEvent, :count).by(1)

      event = OptionsBuyingSignalEvent.last
      expect(event.event_type).to eq('scoring_decision')
      expect(event.index_key).to eq('NIFTY')
      expect(event.security_id).to eq('12345')
      expect(event.metadata).to include('total_score', 'strategy' => 'orb_breakout', 'direction' => 'bullish')
    end
  end
end
