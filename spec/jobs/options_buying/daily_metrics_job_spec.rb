# frozen_string_literal: true

require 'rails_helper'

RSpec.describe OptionsBuying::DailyMetricsJob, type: :job do
  let(:index_cfg) { { key: 'NIFTY', sid: '13', segment: 'IDX_I' } }
  let(:instrument) { instance_double(Instrument) }

  before do
    allow(IndexConfigLoader).to receive(:load_indices).and_return([index_cfg])
    allow(Instrument).to receive(:find_by).and_return(instrument)
    allow(OptionsBuying::ATRCompressionChecker).to receive(:compute_daily_atr_for).with(instrument).and_return(120.5)
    allow(OptionsBuying::StateStore).to receive(:set_daily_atr)
  end

  describe '#perform' do
    it 'seeds daily ATR for each configured index' do
      expect(OptionsBuying::StateStore).to receive(:set_daily_atr).with('NIFTY', 120.5)

      described_class.perform_now
    end

    context 'when instrument is missing' do
      before do
        allow(Instrument).to receive(:find_by).and_return(nil)
      end

      it 'skips seeding' do
        expect(OptionsBuying::StateStore).not_to receive(:set_daily_atr)

        described_class.perform_now
      end
    end
  end
end
