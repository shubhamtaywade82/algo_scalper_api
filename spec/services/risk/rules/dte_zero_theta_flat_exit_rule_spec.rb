# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Risk::Rules::DteZeroThetaFlatExitRule do
  include ActiveSupport::Testing::TimeHelpers

  subject(:rule) { described_class.new(config: {}) }

  let(:tracker) do
    instance_double(
      PositionTracker,
      order_no: 'ORD001',
      active?: true,
      meta: { 'dte_at_entry' => 0, 'expiry_date' => Date.current.to_s }
    )
  end
  let(:context) do
    instance_double(
      Risk::Rules::RuleContext,
      active?: true,
      pnl_pct: 0.01,
      tracker: tracker
    )
  end

  before do
    allow(AlgoConfig).to receive(:fetch).and_return(
      risk: {
        dte_zero_exit: {
          enabled: true,
          after_time: '12:30',
          min_pnl_pct_to_hold: 0.03
        },
        dte_parameters: {
          enabled: true,
          by_dte: { '0' => { max_entry_time: '12:30' } }
        }
      }
    )
  end

  describe '#evaluate' do
    context 'when 0-DTE position is below hold threshold after cutoff' do
      it 'exits with theta-flat reason' do
        travel_to Time.zone.parse('2026-03-17 13:00:00 +05:30') do
          result = rule.evaluate(context)

          expect(result.exit?).to be(true)
          expect(result.reason).to include('DTE_ZERO_THETA_FLAT')
        end
      end
    end

    context 'when 0-DTE position is above hold threshold' do
      it 'returns no_action' do
        allow(context).to receive(:pnl_pct).and_return(0.04)

        travel_to Time.zone.parse('2026-03-17 13:00:00 +05:30') do
          result = rule.evaluate(context)

          expect(result.no_action?).to be(true)
        end
      end
    end

    context 'when before cutoff time' do
      it 'returns no_action' do
        travel_to Time.zone.parse('2026-03-17 12:00:00 +05:30') do
          result = rule.evaluate(context)

          expect(result.no_action?).to be(true)
        end
      end
    end

    context 'when position is not 0-DTE' do
      it 'returns no_action' do
        allow(tracker).to receive(:meta).and_return('dte_at_entry' => 1)

        travel_to Time.zone.parse('2026-03-17 13:00:00 +05:30') do
          result = rule.evaluate(context)

          expect(result.no_action?).to be(true)
        end
      end
    end
  end
end
