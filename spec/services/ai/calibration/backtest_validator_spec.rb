# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Ai::Calibration::BacktestValidator do
  let(:trades) do
    [
      { entry_price: 100, exit_price: 110, pnl: 1000 }, # +10%
      { entry_price: 100, exit_price: 90, pnl: -1000 },  # -10%
      { entry_price: 100, exit_price: 120, pnl: 2000 }  # +20%
    ]
  end

  let(:proposed_patch) do
    {
      'risk' => {
        'sl_pct' => 0.15,
        'tp_pct' => 0.30
      }
    }
  end

  describe '.call' do
    before do
      allow(AlgoConfig).to receive(:fetch).and_return({
        risk: { sl_pct: 0.10, tp_pct: 0.25 }
      })
    end

    it 'approves if projected PnL is better or within tolerance' do

      result = described_class.call(trades: trades, proposed_patch: proposed_patch)

      expect(result[:approved]).to be true
      expect(result[:baseline_pnl]).to eq(20.0) # 10 - 10 + 20
    end

    it 'rejects if projected PnL regresses significantly' do
      allow(AlgoConfig).to receive(:fetch).and_return({ risk: { sl_pct: 0.10, tp_pct: 0.25 } })

      # Patch that tightens TP too much
      bad_patch = { 'risk' => { 'sl_pct' => 0.20, 'tp_pct' => 0.05 } }

      result = described_class.call(trades: trades, proposed_patch: bad_patch)

      expect(result[:approved]).to be false
      expect(result[:rejection_reason]).to include('worse than baseline')
    end

    it 'returns metrics' do
      result = described_class.call(trades: trades, proposed_patch: proposed_patch)

      expect(result[:baseline_metrics]).to include(:win_rate, :profit_factor, :max_drawdown)
      expect(result[:projected_metrics]).to include(:win_rate, :profit_factor, :max_drawdown)
    end
  end
end
