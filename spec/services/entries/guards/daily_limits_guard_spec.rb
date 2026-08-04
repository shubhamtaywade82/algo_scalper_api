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

      it 'blocks when trades_today reaches the configured per-symbol cap' do
        allow(AlgoConfig).to receive(:fetch).and_return(daily_limits: { enabled: true, max_trades_per_symbol: 3 })
        allow(daily_limits).to receive(:get_daily_trades).with('NIFTY').and_return(3)

        result = described_class.call(context)
        expect(result).to include(blocked: a_string_matching(/daily loss\/profit limits/))
      end

      it 'passes when trades_today is below the configured per-symbol cap' do
        allow(AlgoConfig).to receive(:fetch).and_return(daily_limits: { enabled: true, max_trades_per_symbol: 3 })
        allow(daily_limits).to receive(:get_daily_trades).with('NIFTY').and_return(2)

        expect(described_class.call(context)).to eq(Entries::EntryGuardPipeline::PASS)
      end

      it 'defaults the per-symbol cap to 6 when not configured' do
        allow(daily_limits).to receive(:get_daily_trades).with('NIFTY').and_return(6)

        result = described_class.call(context)
        expect(result).to include(blocked: a_string_matching(/daily loss\/profit limits/))
      end

      it 'uses a per-index override cap when max_trades_per_symbol is a hash' do
        allow(AlgoConfig).to receive(:fetch).and_return(
          daily_limits: { enabled: true, max_trades_per_symbol: { default: 6, per_index: { 'NIFTY' => 20 } } }
        )
        allow(daily_limits).to receive(:get_daily_trades).with('NIFTY').and_return(15)

        expect(described_class.call(context)).to eq(Entries::EntryGuardPipeline::PASS)
      end

      it 'blocks once trades_today reaches the per-index override cap' do
        allow(AlgoConfig).to receive(:fetch).and_return(
          daily_limits: { enabled: true, max_trades_per_symbol: { default: 6, per_index: { 'NIFTY' => 20 } } }
        )
        allow(daily_limits).to receive(:get_daily_trades).with('NIFTY').and_return(20)

        result = described_class.call(context)
        expect(result).to include(blocked: a_string_matching(/daily loss\/profit limits/))
      end

      it 'falls back to the hash default cap for an index with no per-index override' do
        allow(AlgoConfig).to receive(:fetch).and_return(
          daily_limits: { enabled: true, max_trades_per_symbol: { default: 8, per_index: { 'BANKNIFTY' => 20 } } }
        )
        allow(daily_limits).to receive(:get_daily_trades).with('NIFTY').and_return(8)

        result = described_class.call(context)
        expect(result).to include(blocked: a_string_matching(/daily loss\/profit limits/))
      end

      it 'blocks when the underlying daily_limits result disallows for a loss/profit reason' do
        allow(daily_limits).to receive(:get_daily_trades).with('NIFTY').and_return(0)
        allow(daily_limits).to receive(:can_trade?).and_return(allowed: false, reason: 'daily_loss_limit_exceeded')

        result = described_class.call(context)
        expect(result).to include(blocked: a_string_matching(/daily loss\/profit limits/))
      end

      it 'does not block on trade_frequency_limit_exceeded (handled separately by the per-symbol cap)' do
        allow(daily_limits).to receive(:get_daily_trades).with('NIFTY').and_return(0)
        allow(daily_limits).to receive(:can_trade?).and_return(allowed: false, reason: 'trade_frequency_limit_exceeded')

        expect(described_class.call(context)).to eq(Entries::EntryGuardPipeline::PASS)
      end
    end
  end
end
