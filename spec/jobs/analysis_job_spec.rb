# frozen_string_literal: true

require 'rails_helper'

RSpec.describe AnalysisJob do
  describe '#compute_for_index (via send)' do
    let(:instrument) { instance_double(Instrument) }

    before do
      allow(IndexConfigLoader).to receive(:load_indices).and_return(
        [{ key: 'NIFTY', sid: '13', segment: 'IDX_I' }]
      )
      allow(Instrument).to receive(:find_by_sid_and_segment).and_return(instrument)
      allow(AnalysisStore).to receive(:stale_components).with('NIFTY').and_return(%i[ai])
      allow(Ai::GenerativeAiMarketGate).to receive_messages(skip?: true, skip_explanation: 'gated')
    end

    it 'writes AI slot when generative AI gate skips so stale loop stops' do
      allow(AnalysisStore).to receive(:write)

      described_class.new.send(:compute_for_index, 'NIFTY', job_force: false)

      expect(AnalysisStore).to have_received(:write).with('NIFTY', :ai, nil)
    end
  end
end
