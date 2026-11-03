# frozen_string_literal: true

require 'rails_helper'

RSpec.describe AnalysisJob do
  let(:instrument) { instance_double(Instrument, candle_series: series) }
  let(:series) { instance_double(CandleSeries, candles: Array.new(30) { |i| i }) }
  let(:bias_engine) { instance_double(Smc::BiasEngine, details: { decision: :no_trade }, analyze_with_ai: { text: 'ai' }) }

  before do
    allow(IndexConfigLoader).to receive(:load_indices).and_return([{ key: 'NIFTY', sid: '13', segment: 'IDX_I' }])
    allow(Instrument).to receive(:find_by_sid_and_segment).and_return(instrument)
    allow(AnalysisStore).to receive_messages(stale_components: %i[smc ai regime], write: true)
    allow(Smc::BiasEngine).to receive(:new).and_return(bias_engine)
    allow(MarketRegimeDetector).to receive(:new).and_return(instance_double(MarketRegimeDetector, detect: { regime: 'CHOPPY' }))
    allow(Indicators::Supertrend).to receive(:new).and_return(instance_double(Indicators::Supertrend, call: { trend: :bearish, last_value: 101.234 }))
    allow(Ai::GenerativeAiMarketGate).to receive(:skip?).and_return(false)
    allow_any_instance_of(described_class).to receive(:sleep) # rubocop:disable RSpec/AnyInstance
  end

  it 'refreshes only the requested components and never calls the LLM for the recurring run' do
    described_class.perform_now(nil, %w[smc regime])

    expect(AnalysisStore).to have_received(:write).with('NIFTY', :smc, anything)
    expect(AnalysisStore).to have_received(:write)
      .with('NIFTY', :regime, { regime: 'CHOPPY', supertrend: { direction: 'bearish', line: 101.23 } })
    expect(bias_engine).not_to have_received(:analyze_with_ai)
  end
end
