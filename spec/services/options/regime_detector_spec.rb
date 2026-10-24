# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Options::RegimeDetector do
  def make_run(symbol:, avg_retrace_abs: 5.0, avg_loss_abs: 8.0, oc_stddev: 3.0)
    CalibrationRun.create!(
      symbol: symbol, weeks_analyzed: 52, strike_mode: 'atm_plus_minus',
      raw_stats: {
        'avg_gain' => 14.0,
        'avg_retrace_abs' => avg_retrace_abs,
        'avg_loss_abs' => avg_loss_abs,
        'oc_stddev' => oc_stddev
      },
      proposed_patch: {}
    )
  end

  # Stable combined_stats: all metrics exactly at historical mean → no shift
  let(:stable_stats) { { avg_gain: 14.0, avg_retrace_abs: 5.0, avg_loss_abs: 8.0, oc_stddev: 3.0 } }

  describe '.check' do
    context 'with fewer than 12 historical runs' do
      before { 11.times { make_run(symbol: 'NIFTY') } }

      it 'returns shift: false with insufficient_history reason' do
        result = described_class.check(symbol: 'NIFTY', combined_stats: stable_stats)
        expect(result[:shift]).to be false
        expect(result[:reason]).to include('insufficient_history')
      end
    end

    context 'with 12+ stable historical runs (all metrics near mean)' do
      before { 12.times { make_run(symbol: 'NIFTY') } }

      it 'returns shift: false when metrics are at the mean' do
        result = described_class.check(symbol: 'NIFTY', combined_stats: stable_stats)
        expect(result[:shift]).to be false
      end
    end

    context 'with a significant avg_retrace_abs spike (> 1.5σ)' do
      before do
        # Establish stable baseline: avg_retrace_abs = 5.0, stddev ≈ 0
        12.times { make_run(symbol: 'NIFTY', avg_retrace_abs: 5.0, avg_loss_abs: 8.0, oc_stddev: 3.0) }
      end

      it 'returns shift: true when avg_retrace_abs spikes far above mean' do
        # Historical mean = 5.0, stddev ≈ 0 → even small deviation → shift
        # Use a clearly high value: 12.0 (well above any reasonable σ band)
        result = described_class.check(symbol: 'NIFTY',
                                       combined_stats: stable_stats.merge(avg_retrace_abs: 12.0))
        expect(result[:shift]).to be true
        expect(result[:reason]).to include('avg_retrace_abs')
      end
    end

    context 'with a significant oc_stddev spike (> 1.5σ)' do
      before do
        # Varied baseline so stddev > 0: alternating 2.5 and 3.5 → mean 3.0, stddev ≈ 0.5
        6.times { make_run(symbol: 'NIFTY', avg_retrace_abs: 5.0, avg_loss_abs: 8.0, oc_stddev: 2.5) }
        6.times { make_run(symbol: 'NIFTY', avg_retrace_abs: 5.0, avg_loss_abs: 8.0, oc_stddev: 3.5) }
      end

      it 'returns shift: true when oc_stddev is well above 1.5σ' do
        # mean ≈ 3.0, stddev ≈ 0.5 → 1.5σ band ≈ 3.75; 6.0 is clearly outside
        result = described_class.check(symbol: 'NIFTY',
                                       combined_stats: stable_stats.merge(oc_stddev: 6.0))
        expect(result[:shift]).to be true
        expect(result[:reason]).to include('oc_stddev')
      end
    end

    context 'when SENSEX and NIFTY runs coexist' do
      before do
        12.times { make_run(symbol: 'NIFTY', avg_retrace_abs: 5.0) }
        12.times { make_run(symbol: 'SENSEX', avg_retrace_abs: 20.0) }
      end

      it 'uses only the correct symbol history (NIFTY spike tests against NIFTY history)' do
        # NIFTY history: avg_retrace_abs = 5.0, stddev ≈ 0 → 12.0 is a spike
        result = described_class.check(symbol: 'NIFTY',
                                       combined_stats: stable_stats.merge(avg_retrace_abs: 12.0))
        expect(result[:shift]).to be true
      end
    end
  end
end
