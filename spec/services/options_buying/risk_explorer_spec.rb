# frozen_string_literal: true

require 'rails_helper'

RSpec.describe OptionsBuying::RiskExplorer do
  let(:algo_config) do
    {
      risk: { sl_pct: 0.15, tp_pct: 0.45, per_trade_risk_pct: 0.015 },
      paper_trading: { enabled: true },
      indices: [
        {
          key: 'NIFTY',
          capital_alloc_pct: 0.5,
          max_same_side: 1,
          max_concurrent_per_index: 2,
          cooldown_sec: 300,
          trade_limits: { max_trades_per_day: 4 }
        }
      ]
    }
  end

  let(:historical_payload) do
    {
      cycles: [
        {
          ce: { max_gain_pct: 50.0, max_loss_pct: -10.0, open_to_close_pct: 5.0 },
          pe: { max_gain_pct: 48.0, max_loss_pct: -12.0, open_to_close_pct: 3.0 }
        },
        {
          ce: { max_gain_pct: 30.0, max_loss_pct: -20.0, open_to_close_pct: -2.0 },
          pe: { max_gain_pct: 55.0, max_loss_pct: -8.0, open_to_close_pct: 8.0 }
        }
      ]
    }
  end

  before do
    allow(AlgoConfig).to receive(:fetch).and_return(algo_config)
    allow(Capital::Allocator).to receive_messages(
      available_cash: 100_000.0,
      deployment_policy: { max_deploy_pct: 0.6 }
    )
    analyzer = instance_double(HistoricalOptionsAnalyzer, analyze: historical_payload)
    allow(HistoricalOptionsAnalyzer).to receive(:new).and_return(analyzer)
    allow(Trading::SegmentExpectancyAnalyzer.instance).to receive(:segment_stats).and_return(
      sample_size: 10,
      win_rate: 0.4,
      expectancy_rupees: 120.0
    )
  end

  describe '.call' do
    it 'returns risk config and deploy readiness' do
      result = described_class.call(index_key: 'NIFTY', weeks: 8)

      expect(result).to include(index_key: 'NIFTY')
      expect(result[:risk_config]).to include(reward_multiple: 3.0, break_even_win_rate: 0.25)
      expect(result[:deploy_readiness][:positive_edge]).to be(true)
    end

    it 'includes historical blended stats and EV grid' do
      result = described_class.call(index_key: 'NIFTY', weeks: 8)

      expect(result[:historical][:available]).to be(true)
      expect(result[:historical][:blended][:target_hit_rate]).to eq(0.75)
      expect(result[:grid][:cells]).not_to be_empty
    end

    context 'when win_probability is passed' do
      it 'uses the override in scenario' do
        result = described_class.call(index_key: 'NIFTY', weeks: 8, win_probability: 0.35)

        expect(result[:scenario][:win_probability]).to eq(0.35)
      end
    end

    context 'when historical analyze fails' do
      before do
        analyzer = instance_double(HistoricalOptionsAnalyzer, analyze: { error: 'no data' })
        allow(HistoricalOptionsAnalyzer).to receive(:new).and_return(analyzer)
      end

      it 'marks historical unavailable' do
        result = described_class.call(index_key: 'NIFTY', weeks: 8)

        expect(result[:historical][:available]).to be(false)
        expect(result[:theta_churn][:risk]).to eq('unknown')
      end
    end
  end
end
