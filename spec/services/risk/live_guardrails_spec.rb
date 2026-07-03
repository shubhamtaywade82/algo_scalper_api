# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Risk::LiveGuardrails do
  describe '#allow_trading?' do
    context 'when equity drawdown is within limits' do
      let(:equity) { [100_000, 101_000, 99_000] }
      let(:trades) { [] }

      it 'returns true' do
        guardrails = described_class.new(equity: equity, trades: trades)
        expect(guardrails.allow_trading?).to be true
      end
    end

    context 'when drawdown exceeds 5%' do
      let(:equity) { [100_000, 105_000, 93_000] }
      let(:trades) { [] }

      it 'returns false' do
        guardrails = described_class.new(equity: equity, trades: trades)
        expect(guardrails.allow_trading?).to be false
      end
    end

    context 'when consecutive losses exceed 5' do
      let(:equity) { [100_000, 100_000, 100_000] }
      let(:trades) do
        (1..5).map { |i| { pnl: -100 * i } }
      end

      it 'returns false' do
        guardrails = described_class.new(equity: equity, trades: trades)
        expect(guardrails.allow_trading?).to be false
      end
    end

    context 'when consecutive losses are exactly at the limit (5 losses)' do
      let(:equity) { [100_000, 100_000, 100_000] }
      let(:trades) do
        (1..5).map { { pnl: -50 } }
      end

      it 'returns false' do
        guardrails = described_class.new(equity: equity, trades: trades)
        expect(guardrails.allow_trading?).to be false
      end
    end

    context 'when fewer than 5 consecutive losses' do
      let(:equity) { [100_000, 100_000, 100_000] }
      let(:trades) do
        [{ pnl: -100 }, { pnl: -200 }, { pnl: 50 }, { pnl: -100 }, { pnl: -50 }]
      end

      it 'returns true' do
        guardrails = described_class.new(equity: equity, trades: trades)
        expect(guardrails.allow_trading?).to be true
      end
    end

    context 'when both drawdown exceeded and consecutive losses exceeded' do
      let(:equity) { [100_000, 105_000, 90_000] }
      let(:trades) do
        (1..6).map { { pnl: -50 } }
      end

      it 'returns false (drawdown check short-circuits)' do
        guardrails = described_class.new(equity: equity, trades: trades)
        expect(guardrails.allow_trading?).to be false
      end
    end

    context 'with empty equity array' do
      let(:equity) { [] }
      let(:trades) { [] }

      it 'returns true (no data to trigger drawdown)' do
        guardrails = described_class.new(equity: equity, trades: trades)
        expect(guardrails.allow_trading?).to be true
      end
    end

    context 'with nil equity values' do
      let(:equity) { [nil, nil] }
      let(:trades) { [] }

      it 'returns true (nil values handled gracefully)' do
        guardrails = described_class.new(equity: equity, trades: trades)
        expect(guardrails.allow_trading?).to be true
      end
    end

    context 'with zero equity values' do
      let(:equity) { [100_000, 0] }
      let(:trades) { [] }

      it 'triggers drawdown check (peak=100k, current=0, drop=100% > 5%)' do
        guardrails = described_class.new(equity: equity, trades: trades)
        expect(guardrails.allow_trading?).to be false
      end
    end

    context 'when equity has only one element' do
      let(:equity) { [100_000] }
      let(:trades) { [] }

      it 'returns true (peak == current, no drawdown)' do
        guardrails = described_class.new(equity: equity, trades: trades)
        expect(guardrails.allow_trading?).to be true
      end
    end

    context 'when trades have zero pnl' do
      let(:equity) { [100_000, 100_000] }
      let(:trades) { [{ pnl: 0 }, { pnl: 0 }, { pnl: 0 }, { pnl: 0 }, { pnl: 0 }] }

      it 'considers zero pnl as a loss (not a win)' do
        guardrails = described_class.new(equity: equity, trades: trades)
        expect(guardrails.allow_trading?).to be false
      end
    end
  end
end
