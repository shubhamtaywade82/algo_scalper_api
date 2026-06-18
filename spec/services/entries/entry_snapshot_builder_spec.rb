# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Entries::EntrySnapshotBuilder do
  let(:index_cfg) { { key: 'NIFTY', segment: 'IDX_I', sid: '13' } }
  let(:pick) { { symbol: 'NIFTY24JUN24500CE', security_id: '999', strike: 24_500, expiry_date: Time.zone.today } }

  before do
    allow(AlgoConfig).to receive(:position_snapshot).and_return(risk: { sl_pct: 0.10, tp_pct: 0.45 })
    allow(Trading::DteResolver).to receive(:days_to_expiry).and_return(0)
    allow(Market::VixGate).to receive(:current_ltp).and_return(14.8)
    allow(AlgoConfig).to receive(:fetch).and_return(
      options_buying: { execution: { max_bid_ask_spread_pct: 0.015 } },
      risk: {
        dte_parameters: {
          enabled: true,
          defaults: { sl_pct: 0.10 },
          by_dte: { '0' => { sl_pct: 0.08, tp_pct: 0.25 } }
        }
      }
    )
  end

  describe '.build' do
    it 'pins DTE risk overrides and analytics fields' do
      result = described_class.build(index_cfg: index_cfg, pick: pick)

      expect(result[:dte_at_entry]).to eq(0)
      expect(result[:vix_at_entry]).to eq(14.8)
      expect(result[:config_snapshot].dig(:risk, :sl_pct)).to eq(0.08)
      expect(result[:config_snapshot].dig(:risk, :tp_pct)).to eq(0.25)
    end
  end
end
