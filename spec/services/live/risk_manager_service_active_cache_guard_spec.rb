# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Live::RiskManagerService do
  describe 'active cache wiring for trailing enforcement' do
    let(:active_cache) { instance_double(Positions::ActiveCache, get_by_tracker_id: nil) }

    it 'initializes active cache in constructor' do
      allow(Positions::ActiveCache).to receive(:instance).and_return(active_cache)

      service = described_class.new

      expect(service.send(:active_cache)).to eq(active_cache)
    end

    it 'does not raise when active cache is unavailable during trailing enforcement' do
      allow(Positions::ActiveCache).to receive(:instance).and_raise(StandardError, 'redis unavailable')
      allow(Rails.logger).to receive(:error)

      service = described_class.new
      tracker = instance_double(PositionTracker, trade_state: 'expansion', be_set?: false, id: 3608)

      expect do
        service.enforce_dynamic_trailing_stops_for(tracker, exit_engine: instance_double(Live::ExitEngine))
      end.not_to raise_error
      expect(Rails.logger).to have_received(:error).with(match(/active_cache unavailable/)).at_least(:once)
    end
  end
end
