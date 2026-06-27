# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Entries::Guards::IndexTradeLimitGuard do
  let(:context) { { index_cfg: { key: 'SENSEX', trade_limits: { max_trades_per_day: max_trades } } } }
  let(:daily_limits) { instance_double(Live::DailyLimits, get_daily_trades: trades_today) }
  let(:trades_today) { 0 }

  before do
    allow(Live::DailyLimits).to receive(:new).and_return(daily_limits)
  end

  describe '.call' do
    context 'when max_trades_per_day is 0' do
      let(:max_trades) { 0 }

      it 'blocks as index paused' do
        result = described_class.call(context)
        expect(result).to eq(blocked: 'index paused SENSEX (max_trades_per_day=0)')
      end
    end

    context 'when max_trades_per_day is unset' do
      let(:context) { { index_cfg: { key: 'NIFTY' } } }

      it 'passes' do
        expect(described_class.call(context)).to eq(Entries::EntryGuardPipeline::PASS)
      end
    end

    context 'when under daily trade limit' do
      let(:max_trades) { 2 }
      let(:trades_today) { 1 }

      it 'passes' do
        expect(described_class.call(context)).to eq(Entries::EntryGuardPipeline::PASS)
      end
    end

    context 'when at daily trade limit' do
      let(:max_trades) { 2 }
      let(:trades_today) { 2 }

      it 'blocks' do
        result = described_class.call(context)
        expect(result).to eq(blocked: 'index trade limit SENSEX (2/2)')
      end
    end
  end
end
