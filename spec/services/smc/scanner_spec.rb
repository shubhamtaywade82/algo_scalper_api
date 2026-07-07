# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Smc::Scanner do
  describe '#process_index (private)' do
    it 'calls StructureEventRecorder.record! for the LTF interval after computing a decision' do
      scanner = described_class.new
      index_cfg = { key: 'NIFTY', sid: '13', segment: 'IDX_I' }
      instrument = create(:instrument, :nifty_index)

      allow(Instrument).to receive(:find_by_sid_and_segment).and_return(instrument)
      bias_engine = instance_double(Smc::BiasEngine, decision: :none, ai_enabled?: false)
      allow(Smc::BiasEngine).to receive(:new).and_return(bias_engine)
      allow(scanner).to receive(:publish_scan_event)
      allow(AlgoConfig).to receive(:fetch).and_return({ signals: { smc_event_store_publish: true } })

      expect(Smc::StructureEventRecorder).to receive(:record!)
        .with(instrument: instrument, interval: Smc::Scanner::STRUCTURE_EVENT_INTERVAL)
        .and_return([])

      scanner.send(:process_index, index_cfg)
    end
  end
end
