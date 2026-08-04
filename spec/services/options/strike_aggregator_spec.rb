# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Options::StrikeAggregator do
  def engine_result(avg_gain:, avg_retrace_abs:, avg_loss_abs:, avg_oc:, oc_stddev: 2.0)
    # Minimal structure matching HistoricalCalibrationEngine#call output
    {
      ce: { avg_gain: avg_gain, avg_loss_abs: avg_loss_abs, avg_retrace_abs: avg_retrace_abs,
            avg_oc: avg_oc, oc_stddev: oc_stddev, avg_entry: 100.0, fee_pct: 0.4, avg_corr_slope: 0.8,
            sessions: { morning_oc: avg_oc * 0.4, midday_oc: avg_oc * 0.3, afternoon_oc: avg_oc * 0.3 } },
      pe: { avg_gain: avg_gain, avg_loss_abs: avg_loss_abs, avg_retrace_abs: avg_retrace_abs,
            avg_oc: avg_oc, oc_stddev: oc_stddev, avg_entry: 100.0, fee_pct: 0.4, avg_corr_slope: -0.8,
            sessions: { morning_oc: avg_oc * 0.4, midday_oc: avg_oc * 0.3, afternoon_oc: avg_oc * 0.3 } }
    }
  end

  describe '.combine' do
    let(:atm)  { engine_result(avg_gain: 20.0, avg_retrace_abs: 4.0, avg_loss_abs: 8.0, avg_oc: 5.0, oc_stddev: 3.0) }
    let(:otm1) { engine_result(avg_gain: 14.0, avg_retrace_abs: 3.0, avg_loss_abs: 6.0, avg_oc: 3.5, oc_stddev: 2.5) }
    let(:otm2) { engine_result(avg_gain: 10.0, avg_retrace_abs: 2.0, avg_loss_abs: 4.0, avg_oc: 2.5, oc_stddev: 2.0) }

    subject(:result) { described_class.combine(atm_stats: atm, otm1_stats: otm1, otm2_stats: otm2) }

    it 'returns a hash with avg_gain, avg_retrace_abs, avg_loss_abs, avg_oc, oc_stddev' do
      expect(result).to include(:avg_gain, :avg_retrace_abs, :avg_loss_abs, :avg_oc, :oc_stddev)
    end

    it 'weights ATM at 0.50, OTM1 at 0.25, OTM2 at 0.25' do
      # avg_gain: ATM=20, OTM1=14, OTM2=10 → 0.5*20 + 0.25*14 + 0.25*10 = 16.0
      expected_gain = (0.50 * 20.0) + (0.25 * 14.0) + (0.25 * 10.0)
      expect(result[:avg_gain]).to be_within(0.01).of(expected_gain)
    end

    it 'returns avg_retrace_abs weighted correctly' do
      # 0.5*4 + 0.25*3 + 0.25*2 = 3.25
      expected = (0.50 * 4.0) + (0.25 * 3.0) + (0.25 * 2.0)
      expect(result[:avg_retrace_abs]).to be_within(0.01).of(expected)
    end

    it 'returns oc_stddev weighted correctly' do
      # 0.5*3.0 + 0.25*2.5 + 0.25*2.0 = 2.625
      expected = (0.50 * 3.0) + (0.25 * 2.5) + (0.25 * 2.0)
      expect(result[:oc_stddev]).to be_within(0.01).of(expected)
    end

    it 'returns avg_loss_abs weighted correctly' do
      # 0.5*8 + 0.25*6 + 0.25*4 = 6.5
      expected = (0.50 * 8.0) + (0.25 * 6.0) + (0.25 * 4.0)
      expect(result[:avg_loss_abs]).to be_within(0.01).of(expected)
    end

    it 'includes sessions with weighted values' do
      expect(result).to have_key(:sessions)
      expect(result[:sessions]).to include(:morning_oc, :midday_oc, :afternoon_oc)
    end

    context 'when all stats are nil' do
      it 'returns zeroed fallback hash' do
        result = described_class.combine(atm_stats: nil, otm1_stats: nil, otm2_stats: nil)
        expect(result[:avg_gain]).to eq(0.0)
        expect(result[:oc_stddev]).to eq(0.0)
        expect(result[:sessions][:morning_oc]).to eq(0.0)
      end
    end

    context 'when otm2_stats is nil (DhanHQ fetch failed)' do
      it 'falls back to ATM=0.67 OTM1=0.33 weighting' do
        result = described_class.combine(atm_stats: atm, otm1_stats: otm1, otm2_stats: nil)
        # 2/3 * 20 + 1/3 * 14 ≈ 18.0
        expected = (2.0 / 3.0 * 20.0) + (1.0 / 3.0 * 14.0)
        expect(result[:avg_gain]).to be_within(0.1).of(expected)
      end
    end

    context 'when only atm_stats is available' do
      it 'returns ATM stats directly' do
        result = described_class.combine(atm_stats: atm, otm1_stats: nil, otm2_stats: nil)
        expect(result[:avg_gain]).to be_within(0.01).of(20.0)
      end
    end
  end
end
