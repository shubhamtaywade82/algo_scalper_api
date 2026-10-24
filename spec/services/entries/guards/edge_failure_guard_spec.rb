# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Entries::Guards::EdgeFailureGuard do
  describe '.call' do
    let(:context) { { index_cfg: { key: 'NIFTY' } } }
    let(:edge_failure_detector) { instance_double(Live::EdgeFailureDetector) }

    before do
      allow(Live::EdgeFailureDetector).to receive(:instance).and_return(edge_failure_detector)
    end

    context 'when edge failure detector is not paused' do
      before do
        allow(edge_failure_detector).to receive(:entries_paused?).with(index_key: 'NIFTY').and_return({ paused: false })
      end

      it 'allows entry' do
        result = described_class.call(context)
        expect(result).to eq(Entries::EntryGuardPipeline::PASS)
      end
    end

    context 'when edge failure detector is paused' do
      let(:resume_time) { 1.hour.from_now }

      before do
        allow(edge_failure_detector).to receive(:entries_paused?).with(index_key: 'NIFTY').and_return({
                                                                                                          paused: true,
                                                                                                          reason: 'consecutive_losses',
                                                                                                          resume_at: resume_time
                                                                                                        })
      end

      it 'blocks entry with reason and resume time' do
        result = described_class.call(context)
        expect(result).to include(blocked: /edge failure/)
        expect(result[:blocked]).to include('consecutive_losses')
        expect(result[:blocked]).to include(resume_time.strftime('%H:%M IST'))
      end
    end

    context 'when edge failure detector is paused with manual override' do
      before do
        allow(edge_failure_detector).to receive(:entries_paused?).with(index_key: 'NIFTY').and_return({
                                                                                                          paused: true,
                                                                                                          reason: 'daily_loss_limit',
                                                                                                          resume_at: nil
                                                                                                        })
      end

      it 'blocks entry with manual override message' do
        result = described_class.call(context)
        expect(result).to include(blocked: /edge failure/)
        expect(result[:blocked]).to include('manual override')
      end
    end
  end
end
