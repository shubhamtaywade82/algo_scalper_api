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
    context 'with a specific symbol' do
      it 'runs AutoCalibrator for that symbol only' do
        described_class.new.perform('NIFTY', 52)
        expect(Options::AutoCalibrator).to have_received(:call).with(symbol: 'NIFTY', weeks: 52).once
        expect(Options::AutoCalibrator).not_to have_received(:call).with(symbol: 'SENSEX', weeks: 52)
      end

      it 'calls propose_config! on the returned run' do
        described_class.new.perform('NIFTY', 52)
        expect(mock_run).to have_received(:propose_config!)
      end

      it 'notifies via CalibrationNotifier' do
        described_class.new.perform('NIFTY', 52)
        expect(Options::CalibrationNotifier).to have_received(:notify).with('NIFTY', mock_run)
      end
    end

    context 'with nil symbol (both indices)' do
      it 'runs AutoCalibrator for NIFTY and SENSEX' do
        described_class.new.perform
        expect(Options::AutoCalibrator).to have_received(:call).with(symbol: 'NIFTY', weeks: 52)
        expect(Options::AutoCalibrator).to have_received(:call).with(symbol: 'SENSEX', weeks: 52)
      end
    end

    context 'when AutoCalibrator returns nil (all fetches failed)' do
      before { allow(Options::AutoCalibrator).to receive(:call).and_return(nil) }

      it 'calls notify_error' do
        described_class.new.perform('NIFTY', 52)
        expect(Options::CalibrationNotifier).to have_received(:notify_error)
      end

      it 'does not raise' do
        expect { described_class.new.perform('NIFTY', 52) }.not_to raise_error
      end
    end

    context 'when NIFTY raises an exception' do
      before do
        allow(Options::AutoCalibrator).to receive(:call) do |symbol:, **|
          raise StandardError, 'NIFTY exploded' if symbol == 'NIFTY'

          mock_run
        end
      end

      it 'still runs SENSEX' do
        described_class.new.perform # nil symbol → both
        expect(Options::AutoCalibrator).to have_received(:call).with(symbol: 'SENSEX', weeks: 52)
      end

      it 'calls notify_error for NIFTY' do
        described_class.new.perform
        expect(Options::CalibrationNotifier).to have_received(:notify_error).with('NIFTY', anything)
      end
    end
  end
end
