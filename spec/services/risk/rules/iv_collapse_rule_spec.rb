# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Risk::Rules::IvCollapseRule do
  let(:watchable) do
    double('watchable', strike_price: 22000.0, option_type: 'CE', expiry_date: Date.current)
  end

  let(:instrument) do
    double('instrument', symbol_name: 'NIFTY')
  end

  let(:tracker) do
    instance_double(
      PositionTracker,
      active?: true,
      meta: { 'iv_at_entry' => 20.0 },
      watchable: watchable,
      underlying_instrument: instrument
    )
  end

  let(:context) do
    Risk::Rules::RuleContext.new(
      position: OpenStruct.new(pnl_pct: 0.05),
      tracker: tracker,
      risk_config: {
        time_overrides: {
          iv_collapse: {
            enabled: true,
            collapse_threshold: 0.15
          }
        }
      }
    )
  end

  let(:rule) { described_class.new(config: {}) }

  describe '#evaluate' do
    before do
      # Mock instrument fetch_option_chain
      allow(instrument).to receive(:fetch_option_chain).and_return(
        {
          oc: {
            '22000.0' => {
              'ce' => { 'implied_volatility' => current_iv }
            }
          }
        }
      )
    end

    context 'when IV collapses past threshold' do
      let(:current_iv) { 16.0 } # 20% drop (from 20.0 to 16.0)

      it 'triggers exit with IV_COLLAPSE reason' do
        result = rule.evaluate(context)
        expect(result).to be_exit
        expect(result.reason).to eq('IV_COLLAPSE')
        expect(result.metadata[:iv_drop_pct]).to eq(20.0)
      end
    end

    context 'when IV drops but not past threshold' do
      let(:current_iv) { 18.0 } # 10% drop

      it 'does not exit' do
        result = rule.evaluate(context)
        expect(result).to be_no_action
      end
    end
  end
end
