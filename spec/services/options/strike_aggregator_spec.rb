# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Options::StrikeAggregator do
  def engine_result(avg_gain:, avg_retrace_abs:, avg_loss_abs:, avg_oc:, oc_stddev: 2.0)
    {
      ce: {
        avg_gain: avg_gain, avg_loss_abs: avg_loss_abs, avg_retrace_abs: avg_retrace_abs,
        avg_oc: avg_oc, oc_stddev: oc_stddev,
        sessions: { morning_oc: avg_oc * 0.4, midday_oc: avg_oc * 0.3, afternoon_oc: avg_oc * 0.3 }
      },
      pe: {
        avg_gain: avg_gain, avg_loss_abs: avg_loss_abs, avg_retrace_abs: avg_retrace_abs,
        avg_oc: avg_oc, oc_stddev: oc_stddev,
        sessions: { morning_oc: avg_oc * 0.4, midday_oc: avg_oc * 0.3, afternoon_oc: avg_oc * 0.3 }
      }
    }
  end

  describe '.combine' do
    let(:atm) { engine_result(avg_gain: 20.0, avg_retrace_abs: 4.0, avg_loss_abs: 8.0, avg_oc: 5.0, oc_stddev: 3.0) }
    let(:otm1) { engine_result(avg_gain: 14.0, avg_retrace_abs: 3.0, avg_loss_abs: 6.0, avg_oc: 3.5, oc_stddev: 2.5) }
    let(:otm2) { engine_result(avg_gain: 10.0, avg_retrace_abs: 2.0, avg_loss_abs: 4.0, avg_oc: 2.5, oc_stddev: 2.0) }

    it 'weights ATM at 0.50, OTM1 at 0.25, OTM2 at 0.25' do
      result = described_class.combine(atm_stats: atm, otm1_stats: otm1, otm2_stats: otm2)
      expected_gain = (0.50 * 20.0) + (0.25 * 14.0) + (0.25 * 10.0)
      expect(result[:avg_gain]).to be_within(0.01).of(expected_gain)
    end

    context 'when only atm_stats is available' do
      it 'returns ATM stats directly' do
        result = described_class.combine(atm_stats: atm, otm1_stats: nil, otm2_stats: nil)
        expect(result[:avg_gain]).to be_within(0.01).of(20.0)
      end
    end
  end
end
