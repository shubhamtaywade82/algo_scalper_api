# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Positions::ExitedPnlReconciler do
  describe '.call' do
    let(:base_attrs) do
      {
        status: 'exited',
        segment: 'NSE_FNO',
        security_id: '55111',
        order_no: "EXITPNL#{SecureRandom.hex(4)}",
        entry_price: BigDecimal('150'),
        exit_price: BigDecimal('127.5'),
        quantity: 25,
        exited_at: 1.hour.ago,
        last_pnl_rupees: BigDecimal('1998'),
        last_pnl_pct: BigDecimal('0.54')
      }
    end

    before do
      allow(Live::RedisPnlCache.instance).to receive(:clear_tracker)
    end

    it 'leaves aligned exited pnl unchanged' do
      tracker = create(:position_tracker, :option_position, **base_attrs)

      truth = Positions::FinalPnl.from_exit_price(
        entry_price: tracker.entry_price,
        quantity: tracker.quantity,
        exit_price: tracker.exit_price,
        is_exited: true
      )
      tracker.update!(last_pnl_rupees: truth[:pnl], last_pnl_pct: truth[:pnl_pct])

      result = described_class.call(tracker: tracker)

      expect(result[:fixed]).to be(false)
      expect(result[:reason]).to eq(:aligned)
    end

    it 'rewrites stale peak pnl from exit_price truth' do # rubocop:disable RSpec/MultipleExpectations
      tracker = create(:position_tracker, :option_position, **base_attrs)
      expected = Positions::FinalPnl.from_exit_price(
        entry_price: tracker.entry_price,
        quantity: tracker.quantity,
        exit_price: tracker.exit_price,
        is_exited: true
      )

      result = described_class.call(tracker: tracker)

      tracker.reload
      expect(result[:fixed]).to be(true)
      expect(tracker.last_pnl_rupees).to eq(expected[:pnl])
      expect(tracker.last_pnl_pct.to_f).to be_within(0.0001).of(expected[:pnl_pct].to_f)
      expect(tracker.execution['final_pnl_pct']).to eq((expected[:pnl_pct].to_f * 100).round(2))
      expect(Live::RedisPnlCache.instance).to have_received(:clear_tracker).with(tracker.id)
    end

    it 'batch-reconciles recent exited trackers' do
      stale = create(:position_tracker, :option_position, **base_attrs)
      create(
        :position_tracker,
        :option_position,
        **base_attrs,
        order_no: "EXITPNL#{SecureRandom.hex(4)}",
        exited_at: 2.days.ago
      )

      stats = described_class.call(since: 1.day.ago)

      stale.reload
      expect(stats[:scanned]).to eq(1)
      expect(stats[:fixed]).to eq(1)
      expect(stale.last_pnl_rupees).not_to eq(BigDecimal('1998'))
    end
  end
end
