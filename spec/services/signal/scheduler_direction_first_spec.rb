# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Signal::Scheduler do
  describe '#evaluate_supertrend_signal' do
    let(:index_cfg) { { key: 'NIFTY', segment: 'IDX_I', sid: '13' } }
    let(:instrument) { instance_double('Instrument') }
    let(:chain_analyzer) { instance_double(Options::ChainAnalyzer) }

    before do
      allow(IndexInstrumentCache.instance).to receive(:get_or_fetch).and_return(instrument)
      allow(Options::ChainAnalyzer).to receive(:new).and_return(chain_analyzer)
      allow(AlgoConfig).to receive(:fetch).and_return(
        indices: [index_cfg],
        chain_analyzer: {},
        signals: {
          primary_timeframe: '1m',
          confirmation_timeframe: '5m',
          supertrend: { period: 10, base_multiplier: 2.0 },
          adx: { min_strength: 20, confirmation_min_strength: 25 }
        }
      )
    end

    it 'returns nil when indicator analysis fails' do
      allow(Signal::Engine).to receive(:analyze_multi_timeframe).and_return(status: :error, message: 'no data')

      scheduler = described_class.new
      expect(scheduler.send(:evaluate_supertrend_signal, index_cfg)).to be_nil
      expect(Options::ChainAnalyzer).not_to have_received(:new)
    end

    it 'skips when indicator returns :avoid' do
      allow(Signal::Engine).to receive(:analyze_multi_timeframe).and_return(
        status: :ok,
        final_direction: :avoid,
        timeframe_results: {}
      )

      scheduler = described_class.new
      expect(scheduler.send(:evaluate_supertrend_signal, index_cfg)).to be_nil
      expect(Options::ChainAnalyzer).not_to have_received(:new)
    end

    it 'builds a signal when indicator direction and chain candidate exist' do
      allow(Signal::Engine).to receive(:analyze_multi_timeframe).and_return(
        status: :ok,
        final_direction: :bullish,
        timeframe_results: { primary: { adx_value: 27 } }
      )
      allow(chain_analyzer).to receive(:select_candidates).and_return([
        { segment: 'NSE_FNO', security_id: '12345', symbol: 'TEST', lot_size: 25 }
      ])

      scheduler = described_class.new
      result = scheduler.send(:evaluate_supertrend_signal, index_cfg)

      expect(result).not_to be_nil
      expect(result[:segment]).to eq('NSE_FNO')
      expect(result[:meta][:direction]).to eq(:bullish)
      expect(result[:meta][:trend_score]).to eq(27)
    end
  end
end

