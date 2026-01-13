# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Risk::Rules::SecureProfitRule do
  let(:instrument) { create(:instrument, :nifty_future) }
  let(:tracker) do
    create(
      :position_tracker,
      instrument: instrument,
      status: 'active',
      entry_price: 100.0,
      quantity: 10
    )
  end
  let(:position_data) do
    Positions::ActiveCache::PositionData.new(
      tracker_id: tracker.id,
      entry_price: 100.0,
      quantity: 10,
      current_ltp: 120.0,
      pnl: 1100.0,
      pnl_pct: 22.0,
      peak_profit_pct: 25.0
    )
  end
  let(:risk_config) do
    {
      secure_profit_threshold_rupees: 1000.0,
      secure_profit_drawdown_pct: 3.0
    }
  end
  let(:context) do
    Risk::Rules::RuleContext.new(
      position: position_data,
      tracker: tracker,
      risk_config: risk_config
    )
  end
  let(:rule) { described_class.new(config: risk_config) }

  describe '#evaluate' do
    context 'when profit exceeds threshold and drawdown triggers' do
      it 'returns exit result when profit >= threshold and drawdown >= threshold' do
        # Peak: 25%, Current: 22%, Drawdown: 3% >= 3% threshold
        result = rule.evaluate(context)
        expect(result.exit?).to be true
        expect(result.reason).to include('secure_profit_exit')
        expect(result.reason).to include('₹1100')
        expect(result.metadata[:pnl_rupees]).to eq(1100.0)
        expect(result.metadata[:peak_profit_pct]).to eq(25.0)
        expect(result.metadata[:current_profit_pct]).to eq(22.0)
        expect(result.metadata[:drawdown]).to eq(3.0)
      end

      it 'triggers exit when drawdown exceeds threshold' do
        position_data.pnl_pct = 20.0 # Drawdown: 5% from peak 25%
        result = rule.evaluate(context)
        expect(result.exit?).to be true
      end
    end

    context 'when profit exceeds threshold but drawdown not triggered' do
      it 'returns no_action when drawdown is below threshold' do
        position_data.pnl_pct = 23.0 # Drawdown: 2% from peak 25% < 3%
        result = rule.evaluate(context)
        expect(result.no_action?).to be true
      end

      it 'allows riding when at peak' do
        position_data.pnl_pct = 25.0 # At peak, no drawdown
        result = rule.evaluate(context)
        expect(result.no_action?).to be true
      end
    end

    context 'when profit is below threshold' do
      it 'returns no_action when profit < threshold' do
        position_data.pnl = 500.0
        position_data.pnl_pct = 5.0
        result = rule.evaluate(context)
        expect(result.no_action?).to be true
      end

      it 'returns no_action when profit exactly equals threshold' do
        position_data.pnl = 1000.0
        position_data.pnl_pct = 10.0
        rule.evaluate(context)
        # Should activate, but check drawdown
        position_data.peak_profit_pct = 10.0
        result = rule.evaluate(context)
        expect(result.no_action?).to be true # No drawdown yet
      end
    end

    context 'when position is exited' do
      it 'returns skip_result' do
        tracker.update(status: 'exited')
        result = rule.evaluate(context)
        expect(result.skip?).to be true
      end
    end

    context 'when profit data is missing' do
      it 'returns skip_result when pnl_rupees is nil' do
        position_data.pnl = nil
        result = rule.evaluate(context)
        expect(result.skip?).to be true
      end

      it 'returns skip_result when pnl_rupees is zero or negative' do
        position_data.pnl = 0
        result = rule.evaluate(context)
        expect(result.skip?).to be true
      end

      it 'returns skip_result when peak_profit_pct is nil' do
        position_data.peak_profit_pct = nil
        result = rule.evaluate(context)
        expect(result.skip?).to be true
      end

      it 'returns skip_result when current_profit_pct is nil' do
        position_data.pnl_pct = nil
        result = rule.evaluate(context)
        expect(result.skip?).to be true
      end
    end

    context 'when threshold is zero' do
      it 'returns skip_result when secure_profit_threshold_rupees is 0' do
        risk_config[:secure_profit_threshold_rupees] = 0
        result = rule.evaluate(context)
        expect(result.skip?).to be true
      end
    end

    context 'with different thresholds' do
      it 'works with ₹500 threshold' do
        risk_config[:secure_profit_threshold_rupees] = 500.0
        position_data.pnl = 600.0
        position_data.pnl_pct = 20.0
        position_data.peak_profit_pct = 25.0
        result = rule.evaluate(context)
        expect(result.exit?).to be true # Drawdown 5% >= 3%
      end

      it 'works with 2% drawdown threshold' do
        risk_config[:secure_profit_drawdown_pct] = 2.0
        position_data.pnl_pct = 22.5 # Drawdown: 2.5% >= 2%
        result = rule.evaluate(context)
        expect(result.exit?).to be true
      end

      it 'works with 5% drawdown threshold' do
        risk_config[:secure_profit_drawdown_pct] = 5.0
        position_data.pnl_pct = 22.0 # Drawdown: 3% < 5%
        result = rule.evaluate(context)
        expect(result.no_action?).to be true
      end
    end

    context 'real-world scenario: securing profit above ₹1000' do
      it 'allows riding when profit grows from ₹1000 to ₹1500' do
        position_data.pnl = 1500.0
        position_data.pnl_pct = 30.0
        position_data.peak_profit_pct = 30.0
        result = rule.evaluate(context)
        expect(result.no_action?).to be true # At peak, no drawdown
      end

      it 'exits when profit drops 3% from peak after securing ₹1000' do
        position_data.pnl = 1400.0
        position_data.pnl_pct = 28.0
        position_data.peak_profit_pct = 30.0 # Drawdown: 2% < 3%
        result = rule.evaluate(context)
        expect(result.no_action?).to be true

        position_data.pnl_pct = 27.0 # Drawdown: 3% >= 3%
        result = rule.evaluate(context)
        expect(result.exit?).to be true
      end
    end

    describe 'priority' do
      it 'has priority 35' do
        expect(described_class::PRIORITY).to eq(35)
      end
    end
  end
end
