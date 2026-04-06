# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Signal::Scheduler do
  describe '#evaluate_supertrend_signal' do
    let(:index_cfg) { { key: 'NIFTY', segment: 'IDX_I', sid: '13' } }
    let(:instrument) { instance_double(Instrument) }

    before do
      allow(IndexInstrumentCache.instance).to receive(:get_or_fetch).and_return(instrument)
      allow(AlgoConfig).to receive(:fetch).and_return(
        indices: [index_cfg],
        chain_analyzer: {},
        feature_flags: { enable_trend_scorer: false, enable_direction_before_chain: false },
        signals: {
          primary_timeframe: '1m',
          confirmation_timeframe: '5m',
          supertrend: { period: 10, base_multiplier: 2.0 },
          adx: { min_strength: 20, confirmation_min_strength: 25 }
        }
      )
    end

    it 'delegates legacy supertrend path to Signal::Engine.run_for and returns nil' do
      allow(Signal::Engine).to receive(:run_for)

      scheduler = described_class.new
      expect(scheduler.send(:evaluate_supertrend_signal, index_cfg)).to be_nil
      expect(Signal::Engine).to have_received(:run_for).with(index_cfg)
    end

    context 'when instrument is missing' do
      before do
        allow(IndexInstrumentCache.instance).to receive(:get_or_fetch).and_return(nil)
      end

      it 'returns nil' do
        scheduler = described_class.new
        expect(scheduler.send(:evaluate_supertrend_signal, index_cfg)).to be_nil
      end
    end
  end
end
