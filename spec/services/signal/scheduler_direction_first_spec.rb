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
    let(:chain_analyzer) { instance_double(Options::ChainAnalyzer) }

    before do
      allow(AlgoConfig).to receive(:fetch).and_return(
        indices: [index_cfg],
        chain_analyzer: {},
        signals: {
          direction_thresholds: { bullish: 14.0, bearish: 7.0 },
          primary_timeframe: '1m',
          confirmation_timeframe: '5m'
        }
      )
      allow(Options::ChainAnalyzer).to receive(:new).and_return(chain_analyzer)
    end

    it 'skips option chain analysis when direction cannot be determined' do
      allow(Signal::TrendScorer).to receive(:compute_direction).and_return({ direction: nil, trend_score: nil })

      expect(Options::ChainAnalyzer).not_to receive(:new)

      scheduler = described_class.new
      result = scheduler.send(:evaluate_strategies_priority, index_cfg, [strategy])

      expect(result).to be_nil
    end

    it 'invokes option chain analyzer after direction resolves and enriches signal meta' do
      allow(Signal::TrendScorer).to receive(:compute_direction).and_return({ direction: :bullish, trend_score: 18 })
      allow(chain_analyzer).to receive(:select_candidates).and_return([
                                                                         {
                                                                           segment: 'NSE_FNO',
                                                                           security_id: '12345',
                                                                           symbol: 'TEST',
                                                                           lot_size: 25
                                                                         }
                                                                       ])

      scheduler = described_class.new
      signal_response = {
        segment: 'NSE_FNO',
        security_id: '12345',
        reason: 'test',
        meta: { candidate_symbol: 'TEST', multiplier: 1 }
      }

      allow(scheduler).to receive(:evaluate_strategy).and_return(signal_response)

      result = scheduler.send(:evaluate_strategies_priority, index_cfg, [strategy])

      expect(result).to eq(signal_response)
      expect(result[:meta][:direction]).to eq(:bullish)
      expect(result[:meta][:trend_score]).to eq(18)
    end
  end
end

