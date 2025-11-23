# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Signal::Scheduler do
  describe '#evaluate_strategies_priority' do
    let(:index_cfg) do
      {
        key: 'NIFTY',
        segment: 'IDX_I',
        sid: '13',
        strategies: {
          open_interest: { enabled: true, priority: 1 }
        }
      }
    end

    let(:strategy) { { key: :open_interest, engine_class: double('EngineClass'), config: {} } }

    let(:base_config) do
      {
        indices: [index_cfg],
        chain_analyzer: {},
        signals: {
          direction_thresholds: { bullish: 14.0, bearish: 7.0 },
          primary_timeframe: '1m',
          confirmation_timeframe: '5m'
        },
        feature_flags: { enable_direction_before_chain: true }
      }
    end

    before do
      allow(AlgoConfig).to receive(:fetch).and_return(base_config)
      allow(IndexInstrumentCache.instance).to receive(:get_or_fetch).and_return(double('Instrument'))
    end

    it 'skips strike selection when direction cannot be determined' do
      scorer = instance_double(Signal::TrendScorer, compute_trend_score: { trend_score: 10 })
      allow(Signal::TrendScorer).to receive(:new).and_return(scorer)

      expect(Options::StrikeSelector).not_to receive(:new)
      expect(Options::DerivativeChainAnalyzer).not_to receive(:new)

      scheduler = described_class.new
      result = scheduler.send(:evaluate_strategies_priority, index_cfg, [strategy])

      expect(result).to be_nil
    end

    it 'invokes strike selector after direction resolves and enriches signal meta' do
      scorer = instance_double(Signal::TrendScorer, compute_trend_score: { trend_score: 18 })
      allow(Signal::TrendScorer).to receive(:new).and_return(scorer)

      selector = instance_double(Options::StrikeSelector)
      allow(Options::StrikeSelector).to receive(:new).and_return(selector)
      allow(selector).to receive(:select).and_return(
        exchange_segment: 'NSE_FNO',
        security_id: '12345',
        option_type: 'CE',
        strike: 26_050,
        derivative: double('Derivative')
      )

      scheduler = described_class.new
      signal_response = {
        segment: 'NSE_FNO',
        security_id: '12345',
        reason: 'test',
        meta: { candidate_symbol: 'TEST', multiplier: 1 }
      }

      allow(scheduler).to receive(:evaluate_strategy).and_return(signal_response)
      expect(Options::DerivativeChainAnalyzer).not_to receive(:new)

      result = scheduler.send(:evaluate_strategies_priority, index_cfg, [strategy])

      expect(result).to eq(signal_response)
      expect(result[:meta][:direction]).to eq(:bullish)
      expect(result[:meta][:trend_score]).to eq(18)
    end
  end
end

