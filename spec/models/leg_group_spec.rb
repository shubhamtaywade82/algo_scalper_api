# frozen_string_literal: true

require 'rails_helper'

RSpec.describe LegGroup do
  describe 'validations' do
    it { is_expected.to validate_presence_of(:group_id) }
    it { is_expected.to validate_presence_of(:strategy_type) }
    it { is_expected.to validate_presence_of(:underlying_symbol) }
    it { is_expected.to validate_presence_of(:expiry) }
    it { is_expected.to validate_inclusion_of(:status).in_array(described_class::STATUSES) }
  end

  describe '#create_from_executor_result!' do
    let(:instrument) { create(:instrument) }
    let(:result) do
      {
        group_id: 'ML_TEST123',
        legs: [
          { leg: { type: :long_put, action: 'buy' }, result: { fill_price: 15.0 }, coid: 'ML_TEST123_L1' },
          { leg: { type: :short_put, action: 'sell' }, result: { fill_price: 35.0 }, coid: 'ML_TEST123_L2' }
        ]
      }
    end

    it 'creates a leg group with active status and associates tracker attributes' do
      group = described_class.create_from_executor_result!(
        result,
        instrument: instrument,
        strategy_type: 'bull_put_spread',
        expiry: Date.current + 3.days,
        quantity: 50
      )

      expect(group).to be_persisted
      expect(group.group_id).to eq('ML_TEST123')
      expect(group.strategy_type).to eq('bull_put_spread')
      expect(group.status).to eq('active')
    end
  end

  describe 'derived trade status (refresh_status!)' do
    let(:instrument) { create(:instrument) }

    def create_group_with_legs(leg_statuses)
      group = create(:leg_group,
                     group_id: "LG_#{SecureRandom.hex(4)}",
                     instrument: instrument,
                     strategy_type: 'bull_call_spread',
                     underlying_symbol: 'NIFTY',
                     expiry: Date.current + 7.days,
                     quantity: 25,
                     status: 'active')

      leg_statuses.each_with_index do |status, index|
        create(:position_tracker, :option_position,
               leg_group: group, leg_index: index, leg_role: "leg_#{index}", status: status)
      end

      group
    end

    it 'stays active while all legs are open' do
      group = create_group_with_legs(%w[active active])

      expect(group.refresh_status!).to eq('active')
      expect(group).to be_open
    end

    it 'becomes partial when one leg has exited and another remains open' do
      group = create_group_with_legs(%w[exited active])

      expect(group.refresh_status!).to eq('partial')
      expect(group).to be_partially_closed
      expect(group).to be_open # the trade is still live
    end

    it 'closes only when every leg has exited' do
      group = create_group_with_legs(%w[exited exited])

      expect(group.refresh_status!).to eq('closed')
      expect(group).not_to be_open
    end

    it 'reports cancelled when all legs were cancelled' do
      group = create_group_with_legs(%w[cancelled cancelled])

      expect(group.refresh_status!).to eq('cancelled')
    end

    it 'is refreshed automatically when a leg status changes' do
      group = create_group_with_legs(%w[active active])
      first_leg = group.position_trackers.order(:leg_index).first

      first_leg.update!(status: :exited, exited_at: Time.current)

      expect(group.reload.status).to eq('partial')
    end
  end

  describe 'P&L rollups' do
    let(:instrument) { create(:instrument) }

    it 'splits realized and unrealized P&L by leg status' do
      group = create(:leg_group,
                     group_id: "LG_#{SecureRandom.hex(4)}",
                     instrument: instrument,
                     strategy_type: 'bull_call_spread',
                     underlying_symbol: 'NIFTY',
                     expiry: Date.current + 7.days,
                     quantity: 25,
                     status: 'partial')

      create(:position_tracker, :option_position, leg_group: group, leg_index: 0, status: 'exited',
                                                  last_pnl_rupees: BigDecimal('500'))
      create(:position_tracker, :option_position, leg_group: group, leg_index: 1, status: 'active',
                                                  last_pnl_rupees: BigDecimal('100'))

      expect(group.realized_pnl_rupees).to eq(500)
    end
  end
end
