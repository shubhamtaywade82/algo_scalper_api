# frozen_string_literal: true

require 'rails_helper'

RSpec.describe AiCalibrationJob, type: :job do
  describe '#perform' do
    it 'calls Runner for each symbol' do
      expect(Ai::Calibration::Runner).to receive(:call).at_least(1).time
      described_class.new.perform
    end

    it 'calls Runner for specific symbol if provided' do
      expect(Ai::Calibration::Runner).to receive(:call).with(symbol: 'NIFTY', days: 14)
      described_class.new.perform('NIFTY', 14)
    end
  end
end
