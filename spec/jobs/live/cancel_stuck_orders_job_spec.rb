# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Live::CancelStuckOrdersJob do
  def tracker_created(seconds_ago, **attrs)
    create(:position_tracker, **attrs).tap do |t|
      t.update_column(:created_at, seconds_ago.ago) # rubocop:disable Rails/SkipsModelValidations
    end
  end

  before do
    allow(Notifications::TelegramNotifier.instance).to receive(:notify_error)
  end

  describe '#perform' do
    it 'ignores paper trackers entirely' do
      tracker_created(90.seconds, paper: true, status: 'active')

      expect(DhanHQ::Models::Order).not_to receive(:find)
      described_class.perform_now
    end

    it 'ignores trackers younger than the check window start' do
      tracker_created(30.seconds, paper: false, status: 'active')

      expect(DhanHQ::Models::Order).not_to receive(:find)
      described_class.perform_now
    end

    it 'ignores trackers older than the check window end' do
      tracker_created(11.minutes, paper: false, status: 'active')

      expect(DhanHQ::Models::Order).not_to receive(:find)
      described_class.perform_now
    end

    it 'leaves a confirmed-filled order untouched' do
      tracker = tracker_created(90.seconds, paper: false, status: 'active')
      allow(DhanHQ::Models::Order).to receive(:find).with(tracker.order_no).and_return(double('order', order_status: 'TRADED')) # rubocop:disable RSpec/VerifiedDoubles

      described_class.perform_now

      expect(tracker.reload.status).to eq('active')
    end

    it 'corrects a tracker that shows active but was actually rejected at the broker' do
      tracker = tracker_created(90.seconds, paper: false, status: 'active')
      allow(DhanHQ::Models::Order).to receive(:find).with(tracker.order_no).and_return(double('order', order_status: 'REJECTED')) # rubocop:disable RSpec/VerifiedDoubles

      described_class.perform_now

      expect(tracker.reload.status).to eq('cancelled')
      expect(Notifications::TelegramNotifier.instance).to have_received(:notify_error)
    end

    it 'cancels an order still unconfirmed (pending) after the check window opens' do
      tracker = tracker_created(90.seconds, paper: false, status: 'active')
      order_double = double('order', order_status: 'PENDING') # rubocop:disable RSpec/VerifiedDoubles
      allow(order_double).to receive(:cancel)
      allow(DhanHQ::Models::Order).to receive(:find).with(tracker.order_no).and_return(order_double)

      described_class.perform_now

      expect(order_double).to have_received(:cancel)
      expect(tracker.reload.status).to eq('cancelled')
      expect(Notifications::TelegramNotifier.instance).to have_received(:notify_error)
    end

    it 'does not cancel the tracker if the order fills in the gap between check and cancel attempt' do
      tracker = tracker_created(90.seconds, paper: false, status: 'active')
      pending_order = double('order', order_status: 'PENDING') # rubocop:disable RSpec/VerifiedDoubles
      allow(pending_order).to receive(:cancel)
      filled_order = double('order', order_status: 'TRADED') # rubocop:disable RSpec/VerifiedDoubles

      # 3 lookups in the cancel path: initial status check, the .cancel call itself
      # (order is still pending at that point), then the post-cancel re-check — which
      # is where we simulate the fill landing in the gap.
      call_count = 0
      allow(DhanHQ::Models::Order).to receive(:find).with(tracker.order_no) do
        call_count += 1
        call_count <= 2 ? pending_order : filled_order
      end

      described_class.perform_now

      expect(tracker.reload.status).to eq('active')
    end
  end
end
