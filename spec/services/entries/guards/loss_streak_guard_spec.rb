# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Entries::Guards::LossStreakGuard do
  describe '.call' do
    let(:context) { { index_cfg: { key: 'NIFTY' } } }
    let(:config) do
      {
        paper_trading: { enabled: true },
        loss_streak_guard: {
          enabled: true,
          consecutive_losses_threshold: 1,
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
          last_pnl_rupees: BigDecimal('-900'),
          exit_reason: 'STOP_LOSS (Sub-second Trigger)',
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

    context 'when live trading and consecutive loss exits reach threshold' do
      let(:context) { { index_cfg: { key: 'SENSEX' } } }

      let(:config) do
        {
          paper_trading: { enabled: false },
          loss_streak_guard: {
            enabled: true,
            consecutive_losses_threshold: 1,
            cooldown_minutes: 30
          }
        }
      end

      before do
        create(
          :position_tracker,
          :exited,
          segment: 'NSE_FNO',
          last_pnl_rupees: BigDecimal('-1200'),
          exit_reason: 'STOP_LOSS (Sub-second Trigger)',
          exited_at: 1.minute.ago,
          meta: { index_key: 'SENSEX' }
        )
      end

      it 'blocks using live position history' do
        result = described_class.call(context)

        expect(result).to include(blocked: 'loss-streak cooldown triggered for SENSEX')
      end
    end
  end
end
