# frozen_string_literal: true

require 'rails_helper'

# enforce_early_trend_failure_for called a calculate_atr_ratio that this class never defined. The retired path
# is not scheduled, so the NoMethodError never surfaced; the integration spec hid it by stubbing the method.
RSpec.describe Live::RiskManagerService, '#calculate_atr_ratio' do
  let(:service) { described_class.new(exit_engine: nil) }
  let(:tracker) { instance_double(PositionTracker) }

  it 'exists and uses the same ATR-ratio rule as the unified exit checker' do
    allow(Live::UnifiedExitChecker).to receive(:calculate_atr_ratio).with(tracker).and_return(1.37)

    expect(service.send(:calculate_atr_ratio, tracker)).to eq(1.37)
  end
end
