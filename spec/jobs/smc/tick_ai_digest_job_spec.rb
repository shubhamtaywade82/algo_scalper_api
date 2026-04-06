# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Smc::TickAiDigestJob do
  include ActiveJob::TestHelper

  let(:instrument) { create(:instrument, :nifty_index) }
  let(:signals_cfg) do
    {
      tick_ai_analysis_enabled: true,
      tick_ai_include_index_ta: false,
      tick_ai_notify_telegram: false,
      smc_confluence_intervals: { htf: '60', mtf: '15', ltf: '5' },
      tick_ai_candle_fetch_delay_seconds: 0.0
    }
  end

  let(:digest) do
    {
      'alignment' => {
        'long_signal' => { '5' => true, '15' => false },
        'short_signal' => { '5' => false, '15' => false },
        'choch_bull' => { '5' => false },
        'choch_bear' => { '5' => false },
        'liq_sweep_bull' => { '5' => false },
        'liq_sweep_bear' => { '5' => false },
        'pdh_sweep' => { '5' => false },
        'pdl_sweep' => { '5' => false }
      }
    }
  end

  before do
    allow(AlgoConfig).to receive(:fetch).and_return({ signals: signals_cfg, ai: { enabled: true } })
    allow(Services::Ai::OllamaClient.instance).to receive_messages(enabled?: true)
    allow(Smc::Confluence::MtfDigest).to receive(:build_from_instrument).and_return(digest)
    allow(Smc::TickAi::SnapshotStore).to receive(:write)
  end

  it 'runs AI when a rising edge is present' do
    prev_flags = Smc::TickAi::EdgeDetector::FLAG_KEYS.index_with { false }
    allow(Smc::TickAi::SnapshotStore).to receive(:read).and_return(prev_flags)

    analyzer_instance = instance_double(Smc::AiAnalyzer, analyze: 'Narrative OK')
    allow(Smc::AiAnalyzer).to receive(:new).and_return(analyzer_instance)
    fake_engine = instance_double(Smc::BiasEngine)
    allow(Smc::BiasEngine).to receive(:new).with(instrument, delay_seconds: 0.0).and_return(fake_engine)
    allow(fake_engine).to receive(:details_without_recursion).with(:call).and_return(
      {
        decision: :call,
        timeframes: {
          htf: { interval: '60', context: {} },
          mtf: { interval: '15', context: {} },
          ltf: { interval: '5', context: {} }
        }
      }
    )
    allow(Trading::AiOutputSanitizer).to receive(:validate!).and_return('Narrative OK')

    described_class.perform_now(instrument_id: instrument.id, ltp: 24_000.0, tick_at: Time.current.iso8601)

    expect(Smc::AiAnalyzer).to have_received(:new).with(
      instrument,
      hash_including(initial_data: hash_including(:tick_trigger))
    )
  end

  it 'skips AI on bootstrap snapshot' do
    allow(Smc::TickAi::SnapshotStore).to receive(:read).and_return({})
    allow(Smc::AiAnalyzer).to receive(:new)

    described_class.perform_now(instrument_id: instrument.id, ltp: 24_000.0)

    expect(Smc::AiAnalyzer).not_to have_received(:new)
  end
end
