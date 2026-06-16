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
      before { allow(OptionsBuying::Mode).to receive(:positional_active?).and_return(true) }

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
  end
end
