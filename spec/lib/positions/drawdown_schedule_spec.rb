# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Positions::DrawdownSchedule do
  let(:config) do
    {
      risk: {
        drawdown: {
          activation_profit_pct: 3.0,
          profit_min: 3.0,
          profit_max: 30.0,
          dd_start_pct: 15.0,
          dd_end_pct: 1.0,
          exponential_k: 3.0,
          index_floors: {
            'NIFTY' => 1.0,
            'BANKNIFTY' => 1.2,
            'SENSEX' => 1.5
          }
        },
        reverse_loss: {
          enabled: true,
          max_loss_pct: 20.0,
          min_loss_pct: 5.0,
          loss_span_pct: 30.0,
          time_tighten_per_min: 2.0,
          atr_penalty_thresholds: [
            { threshold: 0.75, penalty_pct: 3.0 },
            { threshold: 0.60, penalty_pct: 5.0 }
          ]
        }
      }
    }
  end

  before do
    allow(AlgoConfig).to receive(:fetch).and_return(config)
  end

  describe '.allowed_upward_drawdown_pct' do
    context 'when profit is below activation threshold' do
      it 'returns nil for profit < profit_min' do
        expect(described_class.allowed_upward_drawdown_pct(2.0)).to be_nil
        expect(described_class.allowed_upward_drawdown_pct(0.0)).to be_nil
      end
    end

    context 'when profit is at minimum threshold' do
      it 'returns dd_start_pct for profit == profit_min' do
        result = described_class.allowed_upward_drawdown_pct(3.0)
        expect(result).to be_within(0.1).of(15.0)
      end
    end

    context 'when profit is at maximum threshold' do
      it 'returns dd_end_pct for profit >= profit_max' do
        result = described_class.allowed_upward_drawdown_pct(30.0)
        expect(result).to be_within(0.1).of(1.0)
      end

      it 'returns dd_end_pct for profit > profit_max' do
        result = described_class.allowed_upward_drawdown_pct(50.0)
        expect(result).to be_within(0.1).of(1.0)
      end
    end

    context 'with index-specific floors' do
      it 'respects NIFTY floor' do
        result = described_class.allowed_upward_drawdown_pct(30.0, index_key: 'NIFTY')
        expect(result).to be >= 1.0
      end

      it 'respects BANKNIFTY floor' do
        result = described_class.allowed_upward_drawdown_pct(30.0, index_key: 'BANKNIFTY')
        expect(result).to be >= 1.2
      end

      it 'respects SENSEX floor' do
        result = described_class.allowed_upward_drawdown_pct(30.0, index_key: 'SENSEX')
        expect(result).to be >= 1.5
      end
    end

    context 'exponential curve behavior' do
      it 'decreases drawdown as profit increases' do
        dd_5 = described_class.allowed_upward_drawdown_pct(5.0)
        dd_10 = described_class.allowed_upward_drawdown_pct(10.0)
        dd_20 = described_class.allowed_upward_drawdown_pct(20.0)

        expect(dd_5).to be > dd_10
        expect(dd_10).to be > dd_20
        expect(dd_20).to be >= 1.0
      end
    end
  end

  describe '.reverse_dynamic_sl_pct' do
    context 'when pnl is positive' do
      it 'returns nil for positive pnl' do
        expect(described_class.reverse_dynamic_sl_pct(5.0)).to be_nil
        expect(described_class.reverse_dynamic_sl_pct(0.0)).to be_nil
      end
    end

    context 'when reverse_loss is disabled' do
      before do
        config[:risk][:reverse_loss][:enabled] = false
      end

      it 'returns nil' do
        expect(described_class.reverse_dynamic_sl_pct(-10.0)).to be_nil
      end
    end

    context 'when pnl is just below entry' do
      it 'returns max_loss_pct for small losses' do
        result = described_class.reverse_dynamic_sl_pct(-1.0)
        expect(result).to be_within(0.5).of(20.0)
      end
    end

    context 'when pnl reaches loss_span_pct' do
      it 'returns min_loss_pct for -loss_span_pct' do
        result = described_class.reverse_dynamic_sl_pct(-30.0)
        expect(result).to be_within(0.5).of(5.0)
      end

      it 'returns min_loss_pct for losses beyond span' do
        result = described_class.reverse_dynamic_sl_pct(-50.0)
        expect(result).to be_within(0.5).of(5.0)
      end
    end

    context 'with time-based tightening' do
      it 'tightens SL based on time below entry' do
        result_0min = described_class.reverse_dynamic_sl_pct(-10.0, seconds_below_entry: 0)
        result_2min = described_class.reverse_dynamic_sl_pct(-10.0, seconds_below_entry: 120)

        expect(result_2min).to be < result_0min
        expect(result_2min).to be_within(5.0).of(result_0min - 4.0) # 2 min * 2.0% per min
      end
    end

    context 'with ATR penalty thresholds' do
      it 'applies penalty for low ATR ratio (0.75 threshold)' do
        result_normal = described_class.reverse_dynamic_sl_pct(-10.0, atr_ratio: 1.0)
        result_low = described_class.reverse_dynamic_sl_pct(-10.0, atr_ratio: 0.70)

        expect(result_low).to be < result_normal
        expect(result_low).to be_within(1.0).of(result_normal - 3.0)
      end

      it 'applies higher penalty for very low ATR ratio (0.60 threshold)' do
        result_normal = described_class.reverse_dynamic_sl_pct(-10.0, atr_ratio: 1.0)
        result_very_low = described_class.reverse_dynamic_sl_pct(-10.0, atr_ratio: 0.50)

        expect(result_very_low).to be < result_normal
        expect(result_very_low).to be_within(1.0).of(result_normal - 5.0)
      end
    end

    context 'clamping behavior' do
      it 'never returns below min_loss_pct' do
        result = described_class.reverse_dynamic_sl_pct(-30.0, seconds_below_entry: 3600, atr_ratio: 0.5)
        expect(result).to be >= 5.0
      end

      it 'never returns above max_loss_pct' do
        result = described_class.reverse_dynamic_sl_pct(-1.0)
        expect(result).to be <= 20.0
      end
    end
  end

  describe '.sl_price_from_entry' do
    it 'calculates SL price correctly' do
      entry = 100.0
      loss_pct = 10.0

      result = described_class.sl_price_from_entry(entry, loss_pct)
      expect(result).to eq(90.0)
    end

    it 'handles different entry prices' do
      expect(described_class.sl_price_from_entry(50.0, 5.0)).to eq(47.5)
      expect(described_class.sl_price_from_entry(200.0, 15.0)).to eq(170.0)
    end
  end
end
