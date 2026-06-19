# frozen_string_literal: true

require 'rails_helper'

RSpec.describe WeeklyCalibrationJob do
  let(:mock_run) do
    instance_double(CalibrationRun, propose_config!: nil)
  end

  before do
    allow(Options::AutoCalibrator).to receive(:call).and_return(mock_run)
    allow(Options::CalibrationNotifier).to receive(:notify)
    allow(Options::CalibrationNotifier).to receive(:notify_error)
  end

  describe '#perform' do
    it 'runs AutoCalibrator for a specific symbol' do
      described_class.new.perform('NIFTY', 52)
      expect(Options::AutoCalibrator).to have_received(:call).with(symbol: 'NIFTY', weeks: 52).once
    end

    it 'calls propose_config! on the returned run' do
      described_class.new.perform('NIFTY', 52)
      expect(mock_run).to have_received(:propose_config!)
    end

    it 'runs both symbols when symbol is nil' do
      described_class.new.perform
      expect(Options::AutoCalibrator).to have_received(:call).with(symbol: 'NIFTY', weeks: 52)
      expect(Options::AutoCalibrator).to have_received(:call).with(symbol: 'SENSEX', weeks: 52)
    end

    context 'when AutoCalibrator returns nil' do
      before { allow(Options::AutoCalibrator).to receive(:call).and_return(nil) }

      it 'calls notify_error without raising' do
        expect { described_class.new.perform('NIFTY', 52) }.not_to raise_error
        expect(Options::CalibrationNotifier).to have_received(:notify_error)
      end
    end
  end
end
