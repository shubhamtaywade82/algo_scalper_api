# frozen_string_literal: true

require 'rails_helper'

RSpec.describe AiCalibrationJob do
  describe '#perform' do
    before do
      allow(Options::CalibrationAutoApplier).to receive(:call).and_return(
        Options::CalibrationAutoApplier::Result.new(false, nil, true)
      )
      allow(Options::CalibrationNotifier).to receive(:notify_auto_apply_followup)
      allow(Ai::Calibration::Runner).to receive(:call)
    end

    it 'calls Runner for each symbol' do
      described_class.new.perform
      expect(Ai::Calibration::Runner).to have_received(:call).at_least(:once)
    end

    it 'calls Runner for specific symbol if provided' do
      described_class.new.perform('NIFTY', 14)
      expect(Ai::Calibration::Runner).to have_received(:call).with(symbol: 'NIFTY', days: 14)
    end

    it 'attempts auto-apply when Runner returns a run' do
      mock_run = instance_double(CalibrationRun, id: 9, applied_at: nil)
      allow(mock_run).to receive(:reload).and_return(mock_run)
      allow(Ai::Calibration::Runner).to receive(:call).and_return(mock_run)
      described_class.new.perform('NIFTY', 14)
      expect(Options::CalibrationAutoApplier).to have_received(:call).with(run: mock_run, source: :ai)
      expect(Options::CalibrationNotifier).to have_received(:notify_auto_apply_followup).with(
        symbol: 'NIFTY', run: mock_run, auto_apply_result: kind_of(Options::CalibrationAutoApplier::Result)
      )
    end
  end
end
