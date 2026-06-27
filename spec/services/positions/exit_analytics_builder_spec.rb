# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Positions::ExitAnalyticsBuilder do
  let(:tracker) do
    instance_double(
      PositionTracker,
      segment: 'NSE_FNO',
      security_id: '12345',
      expiry_date: Date.current,
      exit_path: 'dte_zero_theta_flat',
      exit_reason: 'DTE_ZERO_THETA_FLAT (0-DTE after 12:30 IST)'
    )
  end

  before do
    allow(Market::VixGate).to receive(:current_ltp).and_return(13.2)
    allow(Live::TimeRegimeService.instance).to receive(:current_regime).and_return(:chop_decay)
    allow(AlgoConfig).to receive(:fetch).and_return(signals: { signal_tier: 'standard' })
    tick = instance_double(MarketTick, bid: 99.0, ask: 100.5, ltp: 100.0)
    allow(Live::TickQuery).to receive(:for_security).and_return(tick)
  end

  describe '.build' do
    it 'returns core exit analytics fields' do
      result = described_class.build(tracker: tracker, exit_price: BigDecimal('100'))

      expect(result).to include(
        vix_at_exit: 13.2,
        dte_at_exit: 0,
        regime_at_exit: 'chop_decay',
        tier_at_exit: 'standard',
        exit_path: 'dte_zero_theta_flat'
      )
    end

    it 'includes spread and timestamp' do
      result = described_class.build(tracker: tracker, exit_price: BigDecimal('100'))

      expect(result[:spread_pct_at_exit]).to be_within(0.0001).of(0.015)
      expect(result[:exit_analytics_at]).to be_present
    end
  end
end
