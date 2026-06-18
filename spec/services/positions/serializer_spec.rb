# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Positions::Serializer do
  describe '.closed' do
    let(:tracker) do
      build_stubbed(
        :position_tracker,
        :exited,
        segment: 'NSE_FNO',
        entry_price: 100.0,
        exit_price: 102.0,
        quantity: 10,
        last_pnl_rupees: 20.0,
        exited_at: Time.zone.parse('2026-06-18 10:00:00 +05:30'),
        meta: {
          'exit_reason' => 'PROFIT_FLOOR_TICK (hwm: ₹350)',
          'exit_path' => 'profit_floor_tick',
          'execution' => { 'classified_as' => 'profit' }
        }
      )
    end

    it 'includes exit_path for dashboard labeling' do
      payload = described_class.closed(tracker)

      expect(payload[:exit_path]).to eq('profit_floor_tick')
      expect(payload[:exit_reason]).to include('PROFIT_FLOOR_TICK')
      expect(payload[:exit_classification]).to eq('profit')
    end
  end
end
