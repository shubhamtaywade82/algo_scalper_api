# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Entries::Guards::DailyLimitsGuard do
  describe '.call' do
    let(:context) { { index_cfg: { key: 'NIFTY' } } }

    context 'when daily limits are disabled' do
      before { allow(AlgoConfig).to receive(:fetch).and_return({}) }

      it 'passes' do
        expect(described_class.call(context)).to eq(Entries::EntryGuardPipeline::PASS)
      end
    end

    context 'when daily limits are enabled' do
      let(:daily_limits) { instance_double(Live::DailyLimits) }

      before do
        allow(AlgoConfig).to receive(:fetch).and_return(daily_limits: { enabled: true })
        allow(Live::DailyLimits).to receive(:new).and_return(daily_limits)
        allow(daily_limits).to receive(:can_trade?).and_return(allowed: true)
      end

      it 'blocks when daily loss limit is exceeded' do
        allow(daily_limits).to receive(:get_daily_trades).with('NIFTY').and_return(0)
        allow(daily_limits).to receive(:can_trade?).and_return(allowed: false, reason: 'daily_loss_limit_exceeded')

        result = described_class.call(context)
        expect(result).to include(blocked: a_string_matching(%r{daily loss/profit limits}))
      end

      it 'blocks when global daily loss limit is exceeded' do
        allow(daily_limits).to receive(:get_daily_trades).with('NIFTY').and_return(0)
        allow(daily_limits).to receive(:can_trade?).and_return(allowed: false, reason: 'global_daily_loss_limit_exceeded')

        result = described_class.call(context)
        expect(result).to include(blocked: a_string_matching(%r{daily loss/profit limits}))
      end

      it 'blocks when daily profit target is reached' do
        allow(daily_limits).to receive(:get_daily_trades).with('NIFTY').and_return(0)
        allow(daily_limits).to receive(:can_trade?).and_return(allowed: false, reason: 'daily_profit_target_reached')

        result = described_class.call(context)
        expect(result).to include(blocked: a_string_matching(%r{daily loss/profit limits}))
      end

      it 'does not block on trade_frequency_limit_exceeded (handled by DailyLimits)' do
        allow(daily_limits).to receive(:get_daily_trades).with('NIFTY').and_return(0)
        allow(daily_limits).to receive(:can_trade?).and_return(allowed: false, reason: 'trade_frequency_limit_exceeded')

        expect(described_class.call(context)).to eq(Entries::EntryGuardPipeline::PASS)
      end

      it 'does not block on global_trade_frequency_limit_exceeded' do
        allow(daily_limits).to receive(:get_daily_trades).with('NIFTY').and_return(0)
        allow(daily_limits).to receive(:can_trade?).and_return(allowed: false, reason: 'global_trade_frequency_limit_exceeded')

        expect(described_class.call(context)).to eq(Entries::EntryGuardPipeline::PASS)
      end

      it 'blocks per-strategy when strategy_slug is provided and limit exceeded' do
        allow(AlgoConfig).to receive(:fetch).and_return(
          daily_limits: { enabled: true },
          strategy_limits: { scalping: { max_trades_per_day: 5 } }
        )
        allow(daily_limits).to receive(:get_daily_trades).with('NIFTY').and_return(0)
        allow(daily_limits).to receive(:can_trade?).and_return(allowed: true)
        allow(daily_limits).to receive(:get_strategy_daily_trades).with('scalping').and_return(5)

        ctx = context.merge(strategy_slug: 'scalping')
        result = described_class.call(ctx)
        expect(result).to include(blocked: a_string_matching(%r{daily loss/profit limits}))
      end

      it 'passes per-strategy when strategy_slug is provided and limit not exceeded' do
        allow(AlgoConfig).to receive(:fetch).and_return(
          daily_limits: { enabled: true },
          strategy_limits: { scalping: { max_trades_per_day: 5 } }
        )
        allow(daily_limits).to receive(:get_daily_trades).with('NIFTY').and_return(0)
        allow(daily_limits).to receive(:can_trade?).and_return(allowed: true)
        allow(daily_limits).to receive(:get_strategy_daily_trades).with('scalping').and_return(3)

        ctx = context.merge(strategy_slug: 'scalping')
        expect(described_class.call(ctx)).to eq(Entries::EntryGuardPipeline::PASS)
      end
    end
  end
end
