# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Orders::Reconciler do
  let(:instrument) { create(:instrument, symbol_name: 'NIFTY', exchange: 'NSE', segment: 'index', security_id: '13') }
  let!(:tracker) { create(:position_tracker, instrument: instrument, watchable: instrument, status: 'active') }

  describe '.call' do
    it 'reconciles active trackers without errors' do
      allow(Orders.config.gateway).to receive(:position).and_return(
        { qty: 65, upnl: 250.0, last_ltp: 155.0 }
      )

      expect(described_class.call).to be >= 1
    end

    it 'marks tracker exited when remote position is missing or closed' do
      allow(Orders.config.gateway).to receive(:position).and_return(
        { qty: 0, upnl: 0.0, last_ltp: 150.0 }
      )

      described_class.new.reconcile_tracker!(tracker)
      expect(tracker.reload.status).to eq('exited')
    end
  end
end
