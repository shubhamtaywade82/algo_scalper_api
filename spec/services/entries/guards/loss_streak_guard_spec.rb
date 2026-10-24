# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Entries::Guards::LossStreakGuard do
  describe '.call' do
    let(:context) { { index_cfg: { key: 'NIFTY' } } }
    let(:config) do
      {
        loss_streak_guard: {
          enabled: true,
          consecutive_losses_threshold: 2,
          cooldown_minutes: 30
        }
      }
    end

    before do
      allow(AlgoConfig).to receive(:fetch).and_return(config)
      Rails.cache.clear
    end

    context 'when guard is disabled' do
      it 'passes entry' do
        allow(AlgoConfig).to receive(:fetch).and_return(loss_streak_guard: { enabled: false })

        result = described_class.call(context)

        expect(result).to eq(Entries::EntryGuardPipeline::PASS)
      end
    end

    context 'when there are not enough consecutive loss exits' do
      before do
        create(
          :position_tracker,
          :paper,
          :exited,
          segment: 'NSE_FNO',
          last_pnl_rupees: BigDecimal('-900'),
          exit_reason: 'STOP_LOSS (Sub-second Trigger)',
          exited_at: Time.current,
          meta: { index_key: 'NIFTY' }
        )
      end

      it 'passes entry' do
        result = described_class.call(context)

        expect(result).to eq(Entries::EntryGuardPipeline::PASS)
      end
    end

    context 'when consecutive loss exits reach threshold' do
      before do
        create(
          :position_tracker,
          :paper,
          :exited,
          segment: 'NSE_FNO',
          last_pnl_rupees: BigDecimal('-1200'),
          exit_reason: 'STOP_LOSS (Sub-second Trigger)',
          exited_at: 1.minute.ago,
          meta: { index_key: 'NIFTY' }
        )
        create(
          :position_tracker,
          :paper,
          :exited,
          segment: 'NSE_FNO',
          last_pnl_rupees: BigDecimal('-800'),
          exit_reason: 'PREMIUM_MOMENTUM_FAILURE (Sub-second Trigger)',
          exited_at: Time.current,
          meta: { index_key: 'NIFTY' }
        )
      end

      it 'blocks and starts cooldown' do
        result = described_class.call(context)

        expect(result).to include(blocked: 'loss-streak cooldown triggered for NIFTY')
      end

      it 'blocks while cooldown is active' do
        described_class.call(context)

        result = described_class.call(context)

        expect(result).to include(blocked: 'loss-streak cooldown active for NIFTY')
      end
    end
  end
end
