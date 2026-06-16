# frozen_string_literal: true

require 'rails_helper'

RSpec.describe OptionsBuying::TelemetrySinkJob, type: :job do
  describe '#perform' do
    it 'persists breakout telemetry events' do
      allow(OptionsBuying::Mode).to receive(:telemetry_sink_enabled?).and_return(true)
      occurred_at = Time.current.iso8601

      expect do
        described_class.perform_now(
          index_key: 'NIFTY',
          security_id: '123',
          event_type: 'breakout_armed',
          occurred_at: occurred_at,
          metadata: { volume_delta: 500, oi_delta: -100 }
        )
      end.to change(OptionsBuyingSignalEvent, :count).by(1)

      event = OptionsBuyingSignalEvent.last
      expect(event.index_key).to eq('NIFTY')
      expect(event.metadata['volume_delta']).to eq(500)
    end
  end
end
