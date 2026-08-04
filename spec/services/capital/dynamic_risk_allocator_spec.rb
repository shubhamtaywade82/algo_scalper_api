# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Capital::DynamicRiskAllocator do
  let(:allocator) { described_class.new }
  let(:base_risk) { 0.03 } # 3% base risk

  before do
    # Mock Capital::Allocator
    allow(Capital::Allocator).to receive_messages(
      available_cash: BigDecimal(100_000),
      deployment_policy: {
        risk_per_trade_pct: base_risk,
        alloc_pct: 0.20,
        daily_max_loss_pct: 0.05
      }
    )
  end

  describe '#risk_pct_for' do
    context 'with trend_score nil' do
      it 'returns base risk' do
        result = allocator.risk_pct_for(index_key: :NIFTY, trend_score: nil)
        expect(result).to eq(base_risk)
      end
    end

    context 'with low trend_score (0-7)' do
      it 'returns reduced risk (0.5x multiplier)' do
        result = allocator.risk_pct_for(index_key: :NIFTY, trend_score: 0.0)
        expect(result).to be < base_risk
        expect(result).to be_within(0.001).of(base_risk * 0.5)
      end

      it 'returns reduced risk for trend_score = 7' do
        result = allocator.risk_pct_for(index_key: :NIFTY, trend_score: 7.0)
        # trend_score 7 normalizes to 7/21 = 0.333, multiplier = 0.5 + (0.333 * 2 * 0.5) = 0.833
        expect(result).to be_within(0.001).of(base_risk * 0.833)
      end
    end

    context 'with medium trend_score (7-14)' do
      it 'returns base risk for trend_score = 10' do
        result = allocator.risk_pct_for(index_key: :NIFTY, trend_score: 10.0)
        expect(result).to be_within(0.001).of(base_risk * 1.0)
      end

      it 'returns slightly increased risk for trend_score = 12' do
        result = allocator.risk_pct_for(index_key: :NIFTY, trend_score: 12.0)
        expect(result).to be > base_risk
        expect(result).to be < base_risk * 1.5
      end
    end

    context 'with high trend_score (14-21)' do
      it 'returns increased risk (1.5x multiplier) for trend_score = 21' do
        result = allocator.risk_pct_for(index_key: :NIFTY, trend_score: 21.0)
        expect(result).to be_within(0.001).of(base_risk * 1.5)
      end

      it 'returns increased risk for trend_score = 18' do
        result = allocator.risk_pct_for(index_key: :NIFTY, trend_score: 18.0)
        expect(result).to be > base_risk
        expect(result).to be <= base_risk * 1.5
      end
    end

    context 'with different indices' do
      it 'uses same base risk for different indices' do
        nifty_risk = allocator.risk_pct_for(index_key: :NIFTY, trend_score: 15.0)
        banknifty_risk = allocator.risk_pct_for(index_key: :BANKNIFTY, trend_score: 15.0)

        expect(nifty_risk).to eq(banknifty_risk)
      end
    end

    context 'with index-specific config override' do
      let(:config) do
        {
          indices: {
            NIFTY: { risk_pct: 0.04 }
          }
        }
      end
      let(:allocator_with_config) { described_class.new(config: config) }

      it 'uses index-specific base risk' do
        result = allocator_with_config.risk_pct_for(index_key: :NIFTY, trend_score: 10.0)
        expect(result).to be_within(0.001).of(0.04) # Uses 0.04 as base, not 0.03
      end

      it 'still scales by trend_score' do
        low_result = allocator_with_config.risk_pct_for(index_key: :NIFTY, trend_score: 0.0)
        high_result = allocator_with_config.risk_pct_for(index_key: :NIFTY, trend_score: 21.0)

        expect(high_result).to be > low_result
        expect(high_result).to be_within(0.001).of(0.04 * 1.5)
      end
    end

    context 'with extreme trend_score values' do
      it 'handles negative trend_score' do
        result = allocator.risk_pct_for(index_key: :NIFTY, trend_score: -10.0)
        expect(result).to be >= 0.0
        expect(result).to be <= base_risk
      end

      it 'handles trend_score > 21' do
        result = allocator.risk_pct_for(index_key: :NIFTY, trend_score: 30.0)
        expect(result).to be <= base_risk * 1.5
      end
    end

    context 'with risk capping' do
      let(:high_base_risk) { 0.08 } # 8% base risk

      before do
        allow(Capital::Allocator).to receive(:deployment_policy).and_return(
          {
            risk_per_trade_pct: high_base_risk,
            alloc_pct: 0.20,
            daily_max_loss_pct: 0.05
          }
        )
      end

      it 'caps risk at 2x base risk' do
        result = allocator.risk_pct_for(index_key: :NIFTY, trend_score: 21.0)
        max_allowed = high_base_risk * 2.0
        expect(result).to be <= max_allowed
      end

      it 'caps risk at 10% absolute maximum' do
        # If base_risk * 1.5 > 0.10, it should cap at 0.10
        result = allocator.risk_pct_for(index_key: :NIFTY, trend_score: 21.0)
        expect(result).to be <= 0.10
      end
    end

    context 'with error handling' do
      before do
        # Mock error in available_cash
        allow(Capital::Allocator).to receive(:available_cash).and_raise(StandardError.new('API error'))
      end

      # rubocop:disable RSpec/MultipleExpectations
      it 'returns fallback base risk on error' do
        # Should still return a value (falls back to default 0.03 = 3%)
        result = allocator.risk_pct_for(index_key: :NIFTY, trend_score: 15.0)
        expect(result).to be_a(Float)
        expect(result).to be >= 0.0
        expect(result).to be <= 1.0
        # Should still scale by trend_score (0.03 * ~1.25 = ~0.0375)
        expect(result).to be > 0.03
        expect(result).to be < 0.05
      end
      # rubocop:enable RSpec/MultipleExpectations

      it 'returns default base risk when trend_score is nil' do
        result = allocator.risk_pct_for(index_key: :NIFTY, trend_score: nil)
        expect(result).to eq(0.03) # Default fallback
      end
    end
  end

  describe 'private methods' do
    describe '#normalize_trend_score' do
      it 'normalizes 0 to 0.0' do
        normalized = allocator.send(:normalize_trend_score, 0.0)
        expect(normalized).to eq(0.0)
      end

      it 'normalizes 21 to 1.0' do
        normalized = allocator.send(:normalize_trend_score, 21.0)
        expect(normalized).to eq(1.0)
      end

      it 'normalizes 10.5 to 0.5' do
        normalized = allocator.send(:normalize_trend_score, 10.5)
        expect(normalized).to eq(0.5)
      end

      it 'clamps values above 21' do
        normalized = allocator.send(:normalize_trend_score, 30.0)
        expect(normalized).to eq(1.0)
      end

      it 'clamps values below 0' do
        normalized = allocator.send(:normalize_trend_score, -5.0)
        expect(normalized).to eq(0.0)
      end
    end

    describe '#scale_by_trend' do
      it 'scales low trend_score to 0.5x multiplier' do
        scaled = allocator.send(:scale_by_trend, 0.0, base_risk)
        expect(scaled).to be_within(0.001).of(base_risk * 0.5)
      end

      it 'scales medium trend_score to 1.0x multiplier' do
        scaled = allocator.send(:scale_by_trend, 10.5, base_risk)
        expect(scaled).to be_within(0.001).of(base_risk * 1.0)
      end

      it 'scales high trend_score to 1.5x multiplier' do
        scaled = allocator.send(:scale_by_trend, 21.0, base_risk)
        expect(scaled).to be_within(0.001).of(base_risk * 1.5)
      end
    end

    describe '#cap_risk' do
      it 'caps at 2x base risk' do
        high_risk = base_risk * 3.0
        capped = allocator.send(:cap_risk, high_risk, base_risk)
        expect(capped).to eq(base_risk * 2.0)
      end

      it 'caps at 10% absolute maximum when 2x base > 0.10' do
        # Use a base_risk where 2x base > 0.10
        high_base = 0.08
        very_high_risk = 0.15
        capped = allocator.send(:cap_risk, very_high_risk, high_base)
        # min(0.15, 0.08*2, 0.10) = min(0.15, 0.16, 0.10) = 0.10
        expect(capped).to eq(0.10)
      end

      it 'caps at 2x base risk when 2x base < 0.10' do
        # Use a base_risk where 2x base < 0.10
        low_base = 0.03
        very_high_risk = 0.15
        capped = allocator.send(:cap_risk, very_high_risk, low_base)
        # min(0.15, 0.03*2, 0.10) = min(0.15, 0.06, 0.10) = 0.06
        expect(capped).to eq(0.06)
      end

      it 'does not cap if within limits' do
        reasonable_risk = base_risk * 1.2
        capped = allocator.send(:cap_risk, reasonable_risk, base_risk)
        expect(capped).to eq(reasonable_risk)
      end
    end
  end
end
