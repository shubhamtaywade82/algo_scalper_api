# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Options::RegimeDetector do
  def make_run(symbol:, avg_retrace_abs: 5.0, avg_loss_abs: 8.0, oc_stddev: 3.0)
    CalibrationRun.create!(
      symbol: symbol,
      weeks_analyzed: 52,
      strike_mode: 'atm_plus_minus',
      raw_stats: {
        'avg_gain' => 14.0,
        'avg_retrace_abs' => avg_retrace_abs,
        'avg_loss_abs' => avg_loss_abs,
        'oc_stddev' => oc_stddev
      },
      proposed_patch: {}
    )
  end

  let(:stable_stats) { { avg_gain: 14.0, avg_retrace_abs: 5.0, avg_loss_abs: 8.0, oc_stddev: 3.0 } }

  describe '.check' do
    context 'with fewer than 12 historical runs' do
      before { 11.times { make_run(symbol: 'NIFTY') } }

      it 'returns shift false with insufficient_history reason' do
        result = described_class.check(symbol: 'NIFTY', combined_stats: stable_stats)
        expect(result[:shift]).to be(false)
        expect(result[:reason]).to include('insufficient_history')
      end
    end

    context 'with a significant avg_retrace_abs spike' do
      before do
        6.times { make_run(symbol: 'NIFTY', avg_retrace_abs: 4.0) }
        6.times { make_run(symbol: 'NIFTY', avg_retrace_abs: 6.0) }
      end

      it 'returns shift true' do
        result = described_class.check(
          symbol: 'NIFTY',
          combined_stats: stable_stats.merge(avg_retrace_abs: 12.0)
        )
        expect(result[:shift]).to be(true)
        expect(result[:reason]).to include('avg_retrace_abs')
      end
    end
  end
end
