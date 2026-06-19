# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Options::HistoricalCalibrationEngine do
  describe '#call' do
    let(:rows) do
      [
        {
          'ce_max_gain_pct' => 20.0, 'ce_max_loss_pct' => -8.0, 'ce_retrace' => -4.0,
          'ce_oc_pct' => 5.0, 'ce_entry' => 100.0, 'ce_corr_slope' => 0.8,
          'ce_morning_oc' => 2.0, 'ce_midday_oc' => 1.0, 'ce_afternoon_oc' => 2.0,
          'pe_max_gain_pct' => 18.0, 'pe_max_loss_pct' => -7.0, 'pe_retrace' => -3.0,
          'pe_oc_pct' => 4.0, 'pe_entry' => 95.0, 'pe_corr_slope' => -0.7,
          'pe_morning_oc' => 1.5, 'pe_midday_oc' => 1.2, 'pe_afternoon_oc' => 1.3
        },
        {
          'ce_max_gain_pct' => 16.0, 'ce_max_loss_pct' => -6.0, 'ce_retrace' => -3.0,
          'ce_oc_pct' => 3.0, 'ce_entry' => 110.0, 'ce_corr_slope' => 0.6,
          'ce_morning_oc' => 1.0, 'ce_midday_oc' => 1.0, 'ce_afternoon_oc' => 1.0,
          'pe_max_gain_pct' => 14.0, 'pe_max_loss_pct' => -5.0, 'pe_retrace' => -2.0,
          'pe_oc_pct' => 2.0, 'pe_entry' => 90.0, 'pe_corr_slope' => -0.5,
          'pe_morning_oc' => 0.8, 'pe_midday_oc' => 0.6, 'pe_afternoon_oc' => 0.6
        }
      ]
    end

    it 'returns CE/PE/combined summaries' do
      result = described_class.new(rows: rows, symbol: 'NIFTY').call

      expect(result[:row_count]).to eq(2)
      expect(result[:ce][:avg_gain]).to eq(18.0)
      expect(result[:pe][:avg_gain]).to eq(16.0)
      expect(result[:combined][:avg_gain]).to eq(17.0)
    end
  end
end
