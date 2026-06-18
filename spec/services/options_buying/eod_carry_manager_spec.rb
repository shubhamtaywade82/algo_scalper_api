# frozen_string_literal: true

require 'rails_helper'

RSpec.describe OptionsBuying::EodCarryManager do
  describe '.run!' do
    context 'when positional mode is off' do
      before { allow(OptionsBuying::Mode).to receive(:positional_active?).and_return(false) }

      it 'tags nothing and returns []' do
        tracker = create(:position_tracker, segment: 'NSE_FNO')
        expect(described_class.run!).to eq([])
        expect(tracker.reload.carry_mode).to be_nil
      end
    end

    context 'when positional mode is on' do
      # Unlimited book budget for the eligibility-focused examples.
      before do
        allow(OptionsBuying::Mode).to receive_messages(positional_active?: true, config: { positional: {} })
      end

      it 'tags only eligible trackers as positional carries' do
        winner = create(:position_tracker, segment: 'NSE_FNO', last_pnl_pct: BigDecimal('0.45'))
        laggard = create(:position_tracker, segment: 'NSE_FNO', last_pnl_pct: BigDecimal('0.05'))

        allow(OptionsBuying::CarryPolicy).to receive(:carry_eligible?).with(winner).and_return(true)
        allow(OptionsBuying::CarryPolicy).to receive(:carry_eligible?).with(laggard).and_return(false)

        result = described_class.run!

        aggregate_failures do
          expect(result).to contain_exactly(winner.order_no)
          expect(winner.reload.carry_mode).to eq('positional')
          expect(winner.carry_roi_pct.to_f).to eq(0.45)
          expect(winner.carry_marked_at).to be_present
          expect(laggard.reload.carry_mode).to be_nil
        end
      end

      it 'skips trackers already tagged' do
        already = create(:position_tracker, segment: 'NSE_FNO')
        already.update!(carry_mode: 'positional')
        allow(OptionsBuying::CarryPolicy).to receive(:carry_eligible?)

        expect(described_class.run!).to eq([])
        expect(OptionsBuying::CarryPolicy).not_to have_received(:carry_eligible?)
      end

      it 'does not raise when a tracker update fails' do
        tracker = create(:position_tracker, segment: 'NSE_FNO', last_pnl_pct: BigDecimal('0.45'))
        allow(PositionTracker).to receive(:active).and_return([tracker])
        allow(OptionsBuying::CarryPolicy).to receive(:carry_eligible?).and_return(true)
        allow(tracker).to receive(:update!).and_raise(StandardError, 'boom')

        expect { described_class.run! }.not_to raise_error
      end
    end

    describe 'book-level carry budget' do
      before do
        allow(OptionsBuying::Mode).to receive(:positional_active?).and_return(true)
        allow(OptionsBuying::CarryPolicy).to receive(:carry_eligible?).and_return(true)
      end

      it 'carries highest-ROI candidates first up to the position cap' do
        allow(OptionsBuying::Mode).to receive(:config).and_return(positional: { max_carry_positions: 2 })
        high = create(:position_tracker, segment: 'NSE_FNO', entry_price: 100, quantity: 50, last_pnl_pct: BigDecimal('0.50'))
        mid  = create(:position_tracker, segment: 'NSE_FNO', entry_price: 100, quantity: 50, last_pnl_pct: BigDecimal('0.40'))
        low  = create(:position_tracker, segment: 'NSE_FNO', entry_price: 100, quantity: 50, last_pnl_pct: BigDecimal('0.30'))

        result = described_class.run!

        expect(result).to contain_exactly(high.order_no, mid.order_no)
        expect(low.reload.carry_mode).to be_nil
      end

      it 'stops carrying once the rupee exposure cap would be exceeded' do
        # each notional = 100 * 50 = 5_000; cap 12_000 fits two, not three
        allow(OptionsBuying::Mode).to receive(:config).and_return(
          positional: { max_carry_exposure_rupees: 12_000 }
        )
        create(:position_tracker, segment: 'NSE_FNO', entry_price: 100, quantity: 50, last_pnl_pct: BigDecimal('0.50'))
        create(:position_tracker, segment: 'NSE_FNO', entry_price: 100, quantity: 50, last_pnl_pct: BigDecimal('0.40'))
        create(:position_tracker, segment: 'NSE_FNO', entry_price: 100, quantity: 50, last_pnl_pct: BigDecimal('0.30'))

        expect(described_class.run!.size).to eq(2)
      end

      it 'counts already-carried positions against the budget' do
        allow(OptionsBuying::Mode).to receive(:config).and_return(positional: { max_carry_positions: 2 })
        existing = create(:position_tracker, segment: 'NSE_FNO', entry_price: 100, quantity: 50)
        existing.update!(carry_mode: 'positional')
        fresh_a = create(:position_tracker, segment: 'NSE_FNO', entry_price: 100, quantity: 50, last_pnl_pct: BigDecimal('0.50'))
        create(:position_tracker, segment: 'NSE_FNO', entry_price: 100, quantity: 50, last_pnl_pct: BigDecimal('0.40'))

        result = described_class.run!

        # one slot left after the existing carry → only the top fresh candidate
        expect(result).to contain_exactly(fresh_a.order_no)
      end
    end
  end
end
