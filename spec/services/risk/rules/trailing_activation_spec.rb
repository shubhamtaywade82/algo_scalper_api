# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Trailing Activation Percentage Rule' do
  let(:instrument) { create(:instrument, :nifty_future) }
  let(:tracker) do
    create(
      :position_tracker,
      instrument: instrument,
      status: 'active',
      entry_price: 100.0,
      quantity: 75
    )
  end

  describe 'RuleContext#trailing_activation_pct' do
    let(:position_data) do
      Positions::PositionData.new(
        tracker_id: tracker.id,
        entry_price: 100.0,
        quantity: 75,
        current_ltp: 105.0,
        pnl: 375.0,
        pnl_pct: 5.0
      )
    end

    context 'with nested config (trailing.activation_pct)' do
      let(:risk_config) do
        {
          trailing: {
            activation_pct: 10.0
          }
        }
      end
      let(:context) do
        Risk::Rules::RuleContext.new(
          position: position_data,
          tracker: tracker,
          risk_config: risk_config
        )
      end

      it 'returns trailing activation percentage from nested config' do
        expect(context.trailing_activation_pct).to eq(BigDecimal('10.0'))
      end
    end

    context 'with flat config (trailing_activation_pct)' do
      let(:risk_config) do
        {
          trailing_activation_pct: 6.66
        }
      end
      let(:context) do
        Risk::Rules::RuleContext.new(
          position: position_data,
          tracker: tracker,
          risk_config: risk_config
        )
      end

      it 'returns trailing activation percentage from flat config' do
        expect(context.trailing_activation_pct).to eq(BigDecimal('6.66'))
      end
    end

    context 'with default value' do
      let(:risk_config) { {} }
      let(:context) do
        Risk::Rules::RuleContext.new(
          position: position_data,
          tracker: tracker,
          risk_config: risk_config
        )
      end

      it 'returns default 10.0 when not configured' do
        expect(context.trailing_activation_pct).to eq(BigDecimal('10.0'))
      end
    end

    context 'with various configurable values' do
      [
        { config: { trailing: { activation_pct: 6.0 } }, expected: 6.0 },
        { config: { trailing: { activation_pct: 6.66 } }, expected: 6.66 },
        { config: { trailing: { activation_pct: 9.99 } }, expected: 9.99 },
        { config: { trailing: { activation_pct: 10.0 } }, expected: 10.0 },
        { config: { trailing: { activation_pct: 13.32 } }, expected: 13.32 },
        { config: { trailing: { activation_pct: 15.0 } }, expected: 15.0 },
        { config: { trailing: { activation_pct: 20.0 } }, expected: 20.0 }
      ].each do |test_case|
        it "handles #{test_case[:expected]}% activation threshold" do
          context = Risk::Rules::RuleContext.new(
            position: position_data,
            tracker: tracker,
            risk_config: test_case[:config]
          )
          expect(context.trailing_activation_pct.to_f).to eq(test_case[:expected])
        end
      end
    end
  end

  describe 'RuleContext#trailing_activated?' do
    let(:position_data) do
      Positions::PositionData.new(
        tracker_id: tracker.id,
        entry_price: 100.0,
        quantity: 75,
        current_ltp: 110.0,
        pnl: 750.0,
        pnl_pct: 10.0
      )
    end
    let(:risk_config) do
      {
        trailing: {
          activation_pct: 10.0
        }
      }
    end
    let(:context) do
      Risk::Rules::RuleContext.new(
        position: position_data,
        tracker: tracker,
        risk_config: risk_config
      )
    end

    context 'when pnl_pct >= activation_pct' do
      it 'returns true when exactly equal' do
        position_data.pnl_pct = 10.0
        expect(context.trailing_activated?).to be true
      end

      it 'returns true when above threshold' do
        position_data.pnl_pct = 15.0
        expect(context.trailing_activated?).to be true
      end
    end

    context 'when pnl_pct < activation_pct' do
      it 'returns false when below threshold' do
        position_data.pnl_pct = 5.0
        expect(context.trailing_activated?).to be false
      end

      it 'returns false when just below threshold' do
        position_data.pnl_pct = 9.99
        expect(context.trailing_activated?).to be false
      end
    end

    context 'when pnl_pct is nil' do
      it 'returns false' do
        position_data.pnl_pct = nil
        expect(context.trailing_activated?).to be false
      end
    end

    context 'with different activation thresholds' do
      it 'works with 6% threshold' do
        risk_config[:trailing][:activation_pct] = 6.0
        position_data.pnl_pct = 6.0
        expect(context.trailing_activated?).to be true

        position_data.pnl_pct = 5.99
        expect(context.trailing_activated?).to be false
      end

      it 'works with 6.66% threshold' do
        risk_config[:trailing][:activation_pct] = 6.66
        position_data.pnl_pct = 6.66
        expect(context.trailing_activated?).to be true

        position_data.pnl_pct = 6.65
        expect(context.trailing_activated?).to be false
      end

      it 'works with 13.32% threshold' do
        risk_config[:trailing][:activation_pct] = 13.32
        position_data.pnl_pct = 13.32
        expect(context.trailing_activated?).to be true

        position_data.pnl_pct = 13.31
        expect(context.trailing_activated?).to be false
      end
    end
  end

  describe 'TrailingStopRule (snapshot-driven)' do
    let(:position_data) do
      Positions::PositionData.new(
        tracker_id: tracker.id,
        entry_price: 100.0,
        quantity: 75,
        current_ltp: 110.0,
        pnl: 750.0,
        pnl_pct: 0.10,
        high_water_mark: 1200.0
      )
    end
    # TrailingStopRule delegates to UnifiedExitChecker, which reads the
    # snapshot (pnl_pct/hwm in decimal format: 0.10 = 10%)
    let(:tracker_snapshot) { { pnl_pct: 0.10, hwm_pnl: 1200.0, pnl: 750.0, ltp: 110.0 } }
    let(:risk_config) do
      {
        trailing: {
          activation_pct: 0.10
        },
        exit_drop_pct: 0.10
      }
    end
    let(:context) do
      Risk::Rules::RuleContext.new(
        position: position_data,
        tracker: tracker,
        risk_config: risk_config,
        tracker_snapshot: tracker_snapshot
      )
    end
    let(:rule) { Risk::Rules::TrailingStopRule.new(config: risk_config) }

    before do
      allow(Live::UnifiedExitChecker).to receive(:evaluate_underlying_context).and_return({ action: :none, multiplier: 1.0 })
    end

    it 'exits when trailing stop is hit' do
      allow(Live::UnifiedExitChecker).to receive(:trailing_stop_hit?).and_return(true)
      result = rule.evaluate(context)
      expect(result.exit?).to be true
      expect(result.reason).to include('TRAILING_STOP')
    end

    it 'exits when underlying context breaks' do
      allow(Live::UnifiedExitChecker).to receive(:evaluate_underlying_context).and_return({ action: :exit, reason: 'STRUCTURE_BREAK' })
      result = rule.evaluate(context)
      expect(result.exit?).to be true
      expect(result.reason).to eq('STRUCTURE_BREAK')
    end

    it 'takes no action when neither exit triggers' do
      allow(Live::UnifiedExitChecker).to receive(:trailing_stop_hit?).and_return(false)
      result = rule.evaluate(context)
      expect(result.no_action?).to be true
    end

    it 'skips when position is not active' do
      tracker.update(status: 'exited')
      result = rule.evaluate(context)
      expect(result.skip?).to be true
    end
  end

  # Risk::Rules::PeakDrawdownRule was deleted — a duplicate of the live
  # Live::TrailingEngine#check_peak_drawdown, which already covers this
  # activation-threshold behavior in spec/services/live/trailing_engine_spec.rb.

  describe 'Real-world scenarios' do
    context 'Scenario A: 10% activation, Entry ₹100, Lot 75' do
      let(:position_data) do
        Positions::PositionData.new(
          tracker_id: tracker.id,
          entry_price: 100.0,
          quantity: 300, # 4 lots × 75
          current_ltp: 110.0, # +10 points
          pnl: 3000.0, # 10% of 30,000 buy value
          pnl_pct: 10.0
        )
      end
      let(:risk_config) do
        {
          trailing: {
            activation_pct: 10.0
          }
        }
      end
      let(:context) do
        Risk::Rules::RuleContext.new(
          position: position_data,
          tracker: tracker,
          risk_config: risk_config
        )
      end

      it 'activates trailing at exactly 10%' do
        expect(context.trailing_activated?).to be true
      end

      it 'does not activate at 9.99%' do
        position_data.pnl_pct = 9.99
        expect(context.trailing_activated?).to be false
      end
    end

    context 'Scenario B: 6% activation, Entry ₹100, Lot 75' do
      let(:position_data) do
        Positions::PositionData.new(
          tracker_id: tracker.id,
          entry_price: 100.0,
          quantity: 300,
          current_ltp: 106.0, # +6 points
          pnl: 1800.0, # 6% of 30,000
          pnl_pct: 6.0
        )
      end
      let(:risk_config) do
        {
          trailing: {
            activation_pct: 6.0
          }
        }
      end
      let(:context) do
        Risk::Rules::RuleContext.new(
          position: position_data,
          tracker: tracker,
          risk_config: risk_config
        )
      end

      it 'activates trailing at 6%' do
        expect(context.trailing_activated?).to be true
      end
    end

    context 'Scenario C: 6.66% activation' do
      let(:position_data) do
        Positions::PositionData.new(
          tracker_id: tracker.id,
          entry_price: 100.0,
          quantity: 300,
          current_ltp: 106.66, # +6.66 points
          pnl: 1998.0, # 6.66% of 30,000
          pnl_pct: 6.66
        )
      end
      let(:risk_config) do
        {
          trailing: {
            activation_pct: 6.66
          }
        }
      end
      let(:context) do
        Risk::Rules::RuleContext.new(
          position: position_data,
          tracker: tracker,
          risk_config: risk_config
        )
      end

      it 'activates trailing at 6.66%' do
        expect(context.trailing_activated?).to be true
      end
    end

    context 'Scenario D: 13.32% activation' do
      let(:position_data) do
        Positions::PositionData.new(
          tracker_id: tracker.id,
          entry_price: 100.0,
          quantity: 300,
          current_ltp: 113.32, # +13.32 points
          pnl: 3996.0, # 13.32% of 30,000
          pnl_pct: 13.32
        )
      end
      let(:risk_config) do
        {
          trailing: {
            activation_pct: 13.32
          }
        }
      end
      let(:context) do
        Risk::Rules::RuleContext.new(
          position: position_data,
          tracker: tracker,
          risk_config: risk_config
        )
      end

      it 'activates trailing at 13.32%' do
        expect(context.trailing_activated?).to be true
      end
    end
  end
end
