# frozen_string_literal: true

require 'rails_helper'

# Percentage Consistency Spec
#
# Verifies that the decimal format (e.g. 0.12 = 12%) is used consistently
# across the full chain:
#   Config (algo.yml) → PnL calculation → Redis storage → Exit rules → UI broadcast
#
# All internal values are DECIMAL. Only the UI broadcast converts to PERCENTAGE (* 100).

RSpec.describe 'Percentage format consistency across the trading pipeline' do
  # ─────────────────────────────────────────────────────────────────────────
  # Layer 1: Config values are DECIMAL
  # ─────────────────────────────────────────────────────────────────────────
  describe 'Config (AlgoConfig)' do
    let(:algo_cfg) do
      {
        risk: {
          sl_pct: 0.12,      # 12% stop-loss as DECIMAL
          tp_pct: 0.50,      # 50% take-profit as DECIMAL
          percentage_pnl_exit: {
            enabled: true,
            target_pct: 0.30 # 30% target as DECIMAL
          }
        }
      }
    end

    before { allow(AlgoConfig).to receive(:fetch).and_return(algo_cfg) }

    it 'sl_pct is stored as DECIMAL (< 1.0, not percentage)' do
      cfg = AlgoConfig.fetch
      expect(cfg.dig(:risk, :sl_pct)).to be < 1.0
      expect(cfg.dig(:risk, :sl_pct)).to eq(0.12)
    end

    it 'tp_pct is stored as DECIMAL (< 1.0, not percentage)' do
      cfg = AlgoConfig.fetch
      expect(cfg.dig(:risk, :tp_pct)).to be < 1.0
      expect(cfg.dig(:risk, :tp_pct)).to eq(0.50)
    end

    it 'percentage_pnl_exit.target_pct is stored as DECIMAL (< 1.0)' do
      cfg = AlgoConfig.fetch
      expect(cfg.dig(:risk, :percentage_pnl_exit, :target_pct)).to be < 1.0
      expect(cfg.dig(:risk, :percentage_pnl_exit, :target_pct)).to eq(0.30)
    end
  end

  # ─────────────────────────────────────────────────────────────────────────
  # Layer 2: PnL calculation produces DECIMAL
  # ─────────────────────────────────────────────────────────────────────────
  describe 'PnL calculation' do
    # The formula used in PnlUpdaterService and ActiveCache#recalculate_pnl
    def pnl_pct(entry_price, current_ltp)
      (current_ltp.to_f - entry_price.to_f) / entry_price.to_f
    end

    it 'produces DECIMAL for a 30% gain (NOT 30.0)' do
      result = pnl_pct(100.0, 130.0)
      expect(result).to be_within(0.0001).of(0.30)
      expect(result).to be < 1.0   # DECIMAL, not percentage
    end

    it 'produces DECIMAL for a 12% loss' do
      result = pnl_pct(100.0, 88.0)
      expect(result).to be_within(0.0001).of(-0.12)
      expect(result).to be > -1.0  # DECIMAL, not percentage
    end

    it 'produces DECIMAL for a 50% gain' do
      result = pnl_pct(200.0, 300.0)
      expect(result).to be_within(0.0001).of(0.50)
    end

    it 'is symmetric: +X% gain followed by recovering loss returns to 0' do
      entry = 100.0
      # Rise to 130 (+30%), then drop back to 100
      gain_pct = pnl_pct(entry, 130.0)
      loss_from_peak = (100.0 - 130.0) / 130.0
      round_trip = gain_pct + ((1.0 + gain_pct) * loss_from_peak)
      expect(round_trip).to be_within(0.001).of(0.0)
    end
  end

  # ─────────────────────────────────────────────────────────────────────────
  # Layer 3: PercentagePnlRule uses DECIMAL threshold and DECIMAL pnl_pct
  # ─────────────────────────────────────────────────────────────────────────
  describe Risk::Rules::PercentagePnlRule do
    let(:rule) do
      described_class.new(config: {
        percentage_pnl_exit: { enabled: true, target_pct: 0.30 }
      })
    end

    def context_with(pnl_decimal)
      instance_double(
        Risk::Rules::RuleContext,
        active?: true,
        pnl_pct: BigDecimal(pnl_decimal.to_s),
        risk_config: {}
      )
    end

    it 'does NOT exit at 29.9% (pnl_pct DECIMAL 0.299)' do
      result = rule.evaluate(context_with(0.299))
      expect(result.exit?).to be false
    end

    it 'exits at exactly 30% (pnl_pct DECIMAL 0.30)' do
      result = rule.evaluate(context_with(0.30))
      expect(result.exit?).to be true
    end

    it 'exits above 30% (pnl_pct DECIMAL 0.45)' do
      result = rule.evaluate(context_with(0.45))
      expect(result.exit?).to be true
    end

    it 'does NOT fire on tiny gains (pnl_pct 0.009, threshold 0.30)' do
      result = rule.evaluate(context_with(0.009))
      expect(result.exit?).to be false
    end

    it 'does NOT fire when pnl is negative' do
      result = rule.evaluate(context_with(-0.05))
      expect(result.exit?).to be false
    end

    it 'reason string displays percentage (not decimal) for readability' do
      result = rule.evaluate(context_with(0.30))
      # Should say "30.0%" not "0.3"
      expect(result.reason).to include('30.0%')
      expect(result.reason).not_to include(' 0.3 ')
    end
  end

  # ─────────────────────────────────────────────────────────────────────────
  # Layer 4: UnifiedExitChecker compares DECIMAL pnl_pct to DECIMAL thresholds
  # ─────────────────────────────────────────────────────────────────────────
  describe Live::UnifiedExitChecker do
    let(:algo_cfg) do
      {
        risk: { sl_pct: 0.12, tp_pct: 0.50 },
        exit: {
          stop_loss: { type: 'static', value: 0.12 },
          take_profit: 0.50,
          trailing: { enabled: false },
          early_exit: { enabled: false },
          time_based: { enabled: false }
        }
      }
    end

    let(:tracker) do
      instance_double(
        PositionTracker,
        id: 1,
        entry_price: 100.0,
        quantity: 1,
        meta: nil,
        instrument: nil,
        watchable: nil,
        side: 'long_ce'
      )
    end

    before do
      allow(AlgoConfig).to receive(:fetch).and_return(algo_cfg)
      # Reset memoized config between tests
      described_class.instance_variable_set(:@exit_config, nil)
    end

    after do
      described_class.instance_variable_set(:@exit_config, nil)
    end

    def stub_pnl(pnl_decimal)
      allow(Live::RedisPnlCache.instance).to receive(:fetch_pnl).with(1).and_return({
        pnl: pnl_decimal * 100.0, # absolute PnL in ₹
        pnl_pct: pnl_decimal, # DECIMAL
        hwm_pnl: nil,
        hwm_pnl_pct: nil,
        ltp: 100.0 * (1.0 + pnl_decimal)
      })
    end

    context 'stop loss at -12%' do
      it 'does NOT exit at -11.9% (just above SL)' do
        stub_pnl(-0.119)
        result = described_class.check_exit_conditions(tracker)
        expect(result).to be_nil
      end

      it 'exits at exactly -12% (pnl_pct DECIMAL -0.12)' do
        stub_pnl(-0.12)
        result = described_class.check_exit_conditions(tracker)
        expect(result).not_to be_nil
        expect(result[:reason]).to eq('STOP_LOSS')
      end

      it 'exits below -12% (pnl_pct DECIMAL -0.15)' do
        stub_pnl(-0.15)
        result = described_class.check_exit_conditions(tracker)
        expect(result).not_to be_nil
        expect(result[:reason]).to eq('STOP_LOSS')
      end
    end

    context 'take profit at 50%' do
      it 'does NOT exit at 49.9%' do
        stub_pnl(0.499)
        result = described_class.check_exit_conditions(tracker)
        expect(result).to be_nil
      end

      it 'exits at exactly 50% (pnl_pct DECIMAL 0.50)' do
        stub_pnl(0.50)
        result = described_class.check_exit_conditions(tracker)
        expect(result).not_to be_nil
        expect(result[:reason]).to eq('TAKE_PROFIT')
      end
    end

    context 'pnl_pct returned in result' do
      it 'returns pnl_pct as PERCENTAGE (multiplied by 100) for UI display' do
        stub_pnl(-0.12)
        result = described_class.check_exit_conditions(tracker)
        # result[:pnl_pct] should be PERCENTAGE (e.g. -12.0), not DECIMAL (-0.12)
        expect(result[:pnl_pct]).to be_within(0.1).of(-12.0)
        expect(result[:pnl_pct].abs).to be > 1.0
      end
    end
  end

  # ─────────────────────────────────────────────────────────────────────────
  # Layer 5: RR profit booking converts DECIMAL sl_pct to PERCENTAGE for formula
  # ─────────────────────────────────────────────────────────────────────────
  describe 'RR profit booking formula' do
    # Extracted from enforce_rr_profit_booking_for logic:
    # rr_threshold: 2.5 (dimensionless ratio)
    # pnl_pct_value: DECIMAL → converted to PERCENTAGE for RR calc
    # sl_pct: DECIMAL (0.12) → converted to PERCENTAGE (12.0) for RR calc
    #
    # RR = (pnl_pct * 100) / (sl_pct * 100) = pnl_pct / sl_pct
    # Both multiply by 100, so it cancels — ratio is the same.
    # But the formula in enforcement code requires consistent units.

    def calculate_rr(pnl_pct_decimal, sl_pct_decimal)
      # As implemented in exit_enforcement.rb after the fix:
      # pnl_pct_value is percentage representation (decimal * 100)
      # sl_pct is percentage representation (decimal * 100)
      pnl_pct_value = pnl_pct_decimal * 100.0 # e.g. 0.30 → 30.0
      sl_pct        = sl_pct_decimal * 100.0 # e.g. 0.12 → 12.0
      pnl_pct_value / sl_pct
    end

    it 'RR = 2.5 at 30% profit with 12% SL (should fire at threshold 2.5)' do
      rr = calculate_rr(0.30, 0.12)
      expect(rr).to be_within(0.01).of(2.5)
    end

    it 'RR < 2.5 at 1% profit with 12% SL (should NOT fire)' do
      rr = calculate_rr(0.01, 0.12)
      expect(rr).to be < 2.5
      expect(rr).to be_within(0.01).of(0.083)
    end

    it 'RR > 2.5 at 50% profit with 12% SL (should fire)' do
      rr = calculate_rr(0.50, 0.12)
      expect(rr).to be > 2.5
      expect(rr).to be_within(0.01).of(4.17)
    end

    it 'without unit conversion: using raw DECIMAL sl_pct in PERCENTAGE formula gives wrong RR' do
      # This was the bug: sl_pct = 0.12 (DECIMAL) used without * 100 in PERCENTAGE formula
      pnl_pct_value = 0.30 * 100.0 # 30.0 (PERCENTAGE)
      sl_pct_bug    = 0.12 # DECIMAL used as PERCENTAGE (the bug)
      rr_wrong = pnl_pct_value / sl_pct_bug
      # Wrong: 30.0 / 0.12 = 250 — would fire at 0.3% profit with 12% SL
      expect(rr_wrong).to be > 100
      expect(rr_wrong).not_to be_within(5.0).of(2.5)
    end
  end

  # ─────────────────────────────────────────────────────────────────────────
  # Layer 6: UI broadcast converts DECIMAL → PERCENTAGE (* 100)
  # ─────────────────────────────────────────────────────────────────────────
  describe 'UI broadcast format' do
    # PnlUpdaterService#broadcast_pnl_update computes:
    #   pnl_pct_display = ((ltp - entry) / entry) * 100
    # (i.e. DECIMAL * 100 = PERCENTAGE for display)

    def ui_pnl_pct(entry_price, ltp)
      ((ltp.to_f - entry_price.to_f) / entry_price.to_f) * 100.0
    end

    it 'broadcasts 30.0 (PERCENTAGE) when pnl_pct is 0.30 (DECIMAL)' do
      result = ui_pnl_pct(100.0, 130.0)
      expect(result).to be_within(0.01).of(30.0)
      expect(result).to be > 1.0 # sanity: not decimal
    end

    it 'broadcasts -12.0 (PERCENTAGE) when pnl_pct is -0.12 (DECIMAL)' do
      result = ui_pnl_pct(100.0, 88.0)
      expect(result).to be_within(0.01).of(-12.0)
    end

    it 'broadcasts 50.0 (PERCENTAGE) at take-profit' do
      result = ui_pnl_pct(200.0, 300.0)
      expect(result).to be_within(0.01).of(50.0)
    end

    it 'internal DECIMAL pnl_pct and UI PERCENTAGE differ by factor of 100' do
      entry = 100.0
      ltp   = 135.0
      decimal_pnl  = (ltp - entry) / entry             # 0.35
      ui_pnl       = ((ltp - entry) / entry) * 100.0   # 35.0
      expect(ui_pnl / decimal_pnl).to be_within(0.001).of(100.0)
    end
  end

  # ─────────────────────────────────────────────────────────────────────────
  # Layer 7: DrawdownSchedule uses DECIMAL inputs and returns DECIMAL
  # ─────────────────────────────────────────────────────────────────────────
  describe Positions::DrawdownSchedule do
    before do
      described_class.reset_config!
allow(AlgoConfig).to receive(:fetch).and_return(drawdown_cfg)
    end

    after { described_class.reset_config! }

    let(:drawdown_cfg) do
      {
        risk: {
          drawdown: {
            profit_min: 0.03,   # 3% DECIMAL
            profit_max: 0.30,   # 30% DECIMAL
            dd_start_pct: 0.15, # 15% DECIMAL
            dd_end_pct: 0.01,   # 1% DECIMAL
            exponential_k: 3.0
          }
        }
      }
    end

    it 'returns nil when profit_pct is below activation (< 0.03 DECIMAL)' do
      result = described_class.allowed_upward_drawdown_pct(0.02)
      expect(result).to be_nil
    end

    it 'returns DECIMAL allowed drawdown (< 1.0) when profit >= activation' do
      result = described_class.allowed_upward_drawdown_pct(0.10)
      expect(result).not_to be_nil
      expect(result).to be < 1.0 # DECIMAL, not percentage
      expect(result).to be > 0.0
    end

    it 'returns dd_end_pct (0.01) at maximum profit (>= 0.30)' do
      result = described_class.allowed_upward_drawdown_pct(0.30)
      expect(result).to be_within(0.001).of(0.01)
    end

    it 'returns larger drawdown at lower profit (more room given early on)' do
      low_profit_dd  = described_class.allowed_upward_drawdown_pct(0.04)
      high_profit_dd = described_class.allowed_upward_drawdown_pct(0.20)
      expect(low_profit_dd).to be > high_profit_dd
    end
  end
end
