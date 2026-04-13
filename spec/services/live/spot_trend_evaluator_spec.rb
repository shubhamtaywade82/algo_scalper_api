# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Live::SpotTrendEvaluator do
  # Include the module under test into a plain object
  let(:evaluator_class) do
    Class.new do
      include Live::SpotTrendEvaluator
    end
  end
  subject(:evaluator) { evaluator_class.new }

  let(:instrument) { instance_double('Instrument') }
  let(:series)     { instance_double('CandleSeries', candles: []) }

  def make_tracker(side: 'long_ce', index_key: 'NIFTY')
    instance_double('PositionTracker',
      side: side,
      meta: { 'index_key' => index_key },
      instrument: instrument,
      watchable: nil)
  end

  before do
    allow(instrument).to receive(:candle_series).with(interval: '1').and_return(series)
    allow(AlgoConfig).to receive(:fetch).and_return({
      risk: { exits: { trailing: { spot_anchored: { min_adx_to_hold: 15 } } } }
    })
  end

  describe '#evaluate_spot_trend_for' do
    context 'when instrument is nil' do
      let(:tracker) { instance_double('PositionTracker', side: 'long_ce',
                        meta: { 'index_key' => 'NIFTY' }, instrument: nil, watchable: nil) }

      it 'returns trend_alive: true (fail-safe — do not exit on missing data)' do
        result = evaluator.evaluate_spot_trend_for(tracker)
        expect(result[:trend_alive]).to be true
        expect(result[:severity]).to eq(:none)
      end
    end

    context 'long_ce with intact trend (supertrend :long_entry, ADX 22, no CHOCH)' do
      let(:tracker) { make_tracker(side: 'long_ce') }
      let(:structure) { instance_double('Smc::Detectors::Structure') }

      before do
        allow(instrument).to receive(:supertrend_signal).with(interval: '1').and_return(:long_entry)
        allow(instrument).to receive(:adx).with(14, interval: '1').and_return(22.0)
        allow(Smc::Detectors::Structure).to receive(:new).with(series).and_return(structure)
        allow(structure).to receive(:choch?).and_return(false)
      end

      it 'returns trend_alive: true' do
        result = evaluator.evaluate_spot_trend_for(tracker)
        expect(result[:trend_alive]).to be true
        expect(result[:supertrend_ok]).to be true
        expect(result[:adx_ok]).to be true
        expect(result[:no_choch]).to be true
      end
    end

    context 'long_ce with supertrend flipped to :short_entry' do
      let(:tracker) { make_tracker(side: 'long_ce') }
      let(:structure) { instance_double('Smc::Detectors::Structure') }

      before do
        allow(instrument).to receive(:supertrend_signal).with(interval: '1').and_return(:short_entry)
        allow(instrument).to receive(:adx).with(14, interval: '1').and_return(22.0)
        allow(Smc::Detectors::Structure).to receive(:new).with(series).and_return(structure)
        allow(structure).to receive(:choch?).and_return(false)
      end

      it 'returns trend_alive: false, severity: :moderate' do
        result = evaluator.evaluate_spot_trend_for(tracker)
        expect(result[:trend_alive]).to be false
        expect(result[:severity]).to eq(:moderate)
        expect(result[:supertrend_ok]).to be false
      end
    end

    context 'long_ce with both supertrend flipped AND ADX collapsed' do
      let(:tracker) { make_tracker(side: 'long_ce') }
      let(:structure) { instance_double('Smc::Detectors::Structure') }

      before do
        allow(instrument).to receive(:supertrend_signal).with(interval: '1').and_return(:short_entry)
        allow(instrument).to receive(:adx).with(14, interval: '1').and_return(10.0)
        allow(Smc::Detectors::Structure).to receive(:new).with(series).and_return(structure)
        allow(structure).to receive(:choch?).and_return(false)
      end

      it 'returns trend_alive: false, severity: :severe' do
        result = evaluator.evaluate_spot_trend_for(tracker)
        expect(result[:trend_alive]).to be false
        expect(result[:severity]).to eq(:severe)
      end
    end

    context 'long_ce with CHOCH detected (trend direction still matches, ADX ok)' do
      let(:tracker) { make_tracker(side: 'long_ce') }
      let(:structure) { instance_double('Smc::Detectors::Structure') }

      before do
        allow(instrument).to receive(:supertrend_signal).with(interval: '1').and_return(:long_entry)
        allow(instrument).to receive(:adx).with(14, interval: '1').and_return(18.0)
        allow(Smc::Detectors::Structure).to receive(:new).with(series).and_return(structure)
        allow(structure).to receive(:choch?).and_return({ type: :bearish, price: 100.0, semantic: :choch })
      end

      it 'returns trend_alive: false, severity: :moderate' do
        result = evaluator.evaluate_spot_trend_for(tracker)
        expect(result[:trend_alive]).to be false
        expect(result[:severity]).to eq(:moderate)
      end
    end

    context 'long_pe with intact bearish trend (supertrend :short_entry)' do
      let(:tracker) { make_tracker(side: 'long_pe', index_key: 'SENSEX') }
      let(:structure) { instance_double('Smc::Detectors::Structure') }

      before do
        allow(instrument).to receive(:supertrend_signal).with(interval: '1').and_return(:short_entry)
        allow(instrument).to receive(:adx).with(14, interval: '1').and_return(25.0)
        allow(Smc::Detectors::Structure).to receive(:new).with(series).and_return(structure)
        allow(structure).to receive(:choch?).and_return(false)
      end

      it 'returns trend_alive: true' do
        result = evaluator.evaluate_spot_trend_for(tracker)
        expect(result[:trend_alive]).to be true
      end
    end
  end
end
