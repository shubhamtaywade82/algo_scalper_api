# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Options::HistoricalCalibrationEngine do
  let(:rows) do
    [
      {
        'symbol' => 'SENSEX',
        'ce_entry' => '100',
        'ce_max_gain_pct' => '22',
        'ce_max_loss_pct' => '-14',
        'ce_oc_pct' => '15',
        'ce_retrace' => '-28',
        'ce_corr_slope' => '2.4',
        'pe_entry' => '105',
        'pe_max_gain_pct' => '18',
        'pe_max_loss_pct' => '-12',
        'pe_oc_pct' => '-9',
        'pe_retrace' => '-25',
        'pe_corr_slope' => '2.1',
        'ce_morning_oc' => '4.2',
        'ce_midday_oc' => '-1.0',
        'ce_afternoon_oc' => '2.1',
        'pe_morning_oc' => '3.8',
        'pe_midday_oc' => '-1.7',
        'pe_afternoon_oc' => '1.5'
      },
      {
        'symbol' => 'SENSEX',
        'ce_entry' => '110',
        'ce_max_gain_pct' => '16',
        'ce_max_loss_pct' => '-11',
        'ce_oc_pct' => '-2',
        'ce_retrace' => '-21',
        'ce_corr_slope' => '1.9',
        'pe_entry' => '120',
        'pe_max_gain_pct' => '24',
        'pe_max_loss_pct' => '-13',
        'pe_oc_pct' => '10',
        'pe_retrace' => '-30',
        'pe_corr_slope' => '2.5',
        'ce_morning_oc' => '2.9',
        'ce_midday_oc' => '-0.8',
        'ce_afternoon_oc' => '1.4',
        'pe_morning_oc' => '3.1',
        'pe_midday_oc' => '-2.2',
        'pe_afternoon_oc' => '1.9'
      }
    ]
  end

  it 'computes ranked profiles' do
    result = described_class.new(rows: rows, symbol: 'SENSEX').call

    expect(result[:row_count]).to eq(2)
    expect(result[:profiles].keys).to contain_exactly(:conservative, :balanced, :aggressive)
    expect(result.dig(:objective, :recommended_profile)).to be_in(%i[conservative balanced aggressive])
  end

  it 'builds bounded suggested patch values' do
    result = described_class.new(rows: rows, symbol: 'SENSEX').call

    expect(result.dig(:suggested_patch, :risk, :percentage_pnl_exit, :target_pct)).to be > 0
    expect(result.dig(:suggested_patch, :risk, :profit_floor, :trail_pct)).to be_between(0.55, 0.92)
    expect(result.dig(:suggested_patch, :risk, :time_stop, :trend, 'SENSEX')).to be >= 6
  end

  it 'returns low confidence warning for small samples' do
    result = described_class.new(rows: rows.first(1), symbol: 'SENSEX').call

    expect(result[:confidence]).to eq(:low)
    expect(result[:warnings].join(' ')).to include('Low sample size')
  end
end
