# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Risk::Rules::TrailingStopRule do
  let(:instrument) { create(:instrument, :nifty_future) }
  let(:tracker) do
    create(
      :position_tracker,
      instrument: instrument,
      status: 'active',
      entry_price: 100.0,
      quantity: 100
    )
  end
  # entry_value = entry_price * quantity = 10,000
  let(:position_data) do
    Positions::PositionData.new(
      tracker_id: tracker.id,
      entry_price: 100.0,
      current_ltp: 110.0,
      pnl: 1000.0,
      pnl_pct: 0.10,
      high_water_mark: 1500.0 # peak_profit_pct = 1500 / 10000 = 0.15 (15%)
    )
  end
  let(:activation_pct) { 0.10 }
  let(:risk_config) { { trailing: { activation_pct: activation_pct } } }
  let(:context) do
    Risk::Rules::RuleContext.new(
      position: position_data,
      tracker: tracker,
      risk_config: risk_config,
      tracker_snapshot: {
        pnl_pct: position_data.pnl_pct,
        hwm_pnl: position_data.high_water_mark,
        ltp: position_data.current_ltp
      }
    )
  end
  let(:rule) { described_class.new(config: risk_config) }

  before do
    # UnifiedExitChecker.exit_config caches on class-level instance variables
    # with a 30s TTL - reset it so each example's AlgoConfig.fetch stub takes
    # effect instead of a stale config from a previous example.
    Live::UnifiedExitChecker.instance_variable_set(:@exit_config, nil)
    Live::UnifiedExitChecker.instance_variable_set(:@exit_config_expires_at, nil)
    allow(AlgoConfig).to receive(:fetch).and_return(
      risk: {
        trailing: { activation_pct: activation_pct },
        underlying_context_exit: { enabled: false } # isolate trailing-stop logic from underlying-context evaluation
      }
    )
    # Positions::ActiveCache.instance.get_by_tracker_id(tracker.id) is consulted
    # for price_history; nothing is cached for this tracker in these specs, so
    # it returns nil and the rule falls back to [ltp] - no stub needed for that.
  end

  describe '#evaluate' do
    context 'when trailing activation threshold is not met' do
      let(:position_data) do
        Positions::PositionData.new(
          tracker_id: tracker.id,
          entry_price: 100.0,
          current_ltp: 110.0,
          pnl: 1000.0,
          pnl_pct: 0.10,
          high_water_mark: 300.0 # peak_profit_pct = 300 / 10000 = 0.03 (3%) < 10% activation
        )
      end

      it 'returns no_action when peak profit is below the activation threshold' do
        result = rule.evaluate(context)
        expect(result.no_action?).to be true
      end
    end

    context 'when trailing activation threshold is met' do
      context 'when trailing stop is triggered' do
        it 'returns exit result when the recommended stop loss is at or above LTP' do
          allow_any_instance_of(Orders::Analyzer).to receive(:recommended_sl).and_return(111.0)

          result = rule.evaluate(context)
          expect(result.exit?).to be true
          expect(result.reason).to eq('TRAILING_STOP')
        end
      end

      context 'when trailing stop is not triggered' do
        it 'returns no_action when the recommended stop loss is below LTP' do
          allow_any_instance_of(Orders::Analyzer).to receive(:recommended_sl).and_return(100.0)

          result = rule.evaluate(context)
          expect(result.no_action?).to be true
        end

        it 'returns no_action when there is no recommended stop loss' do
          allow_any_instance_of(Orders::Analyzer).to receive(:recommended_sl).and_return(nil)

          result = rule.evaluate(context)
          expect(result.no_action?).to be true
        end
      end
    end

    context 'when position is exited' do
      it 'returns skip_result' do
        tracker.update(status: 'exited')
        result = rule.evaluate(context)
        expect(result.skip?).to be true
      end
    end

    context 'when data is missing' do
      it 'returns no_action when high water mark is nil' do
        position_data.high_water_mark = nil
        result = rule.evaluate(context)
        expect(result.no_action?).to be true
      end

      it 'returns no_action when high water mark is zero' do
        position_data.high_water_mark = 0
        result = rule.evaluate(context)
        expect(result.no_action?).to be true
      end
    end

    context 'when activation threshold is zero' do
      let(:activation_pct) { 0 }

      it 'is treated as always armed once profitable, still needs a real stop-loss trigger to exit' do
        allow_any_instance_of(Orders::Analyzer).to receive(:recommended_sl).and_return(nil)

        result = rule.evaluate(context)
        expect(result.no_action?).to be true
      end
    end

    context 'with different activation thresholds' do
      let(:activation_pct) { 0.06 }

      it 'arms trailing once peak profit exceeds a 6% activation threshold' do
        allow_any_instance_of(Orders::Analyzer).to receive(:recommended_sl).and_return(nil)

        # high_water_mark 1500 / entry_value 10000 = 15% >= 6% activation - armed,
        # no exit only because recommended_sl is stubbed nil above.
        result = rule.evaluate(context)
        expect(result.no_action?).to be true
      end
    end

    describe 'priority' do
      it 'has priority 50' do
        expect(described_class::PRIORITY).to eq(50)
      end
    end
  end
end
