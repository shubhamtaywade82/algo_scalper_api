# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Live::RiskManagerService, 'Underlying and Structure Exits' do
  subject(:service) { described_class.new(exit_engine: exit_engine) }

  let(:exit_engine) { instance_double(Live::ExitEngine, execute_exit: true) }
  let(:active_cache) { instance_double(Positions::ActiveCache) }
  let(:watchable) { create(:derivative, :nifty_call_option, security_id: '50001') }
  let(:tracker) do
    create(
      :position_tracker,
      :option_position,
      watchable: watchable,
      instrument: watchable.instrument,
      segment: 'NSE_FNO',
      security_id: watchable.security_id,
      entry_price: 100.0,
      quantity: 25,
      status: :active,
      meta: { 'index_key' => 'NIFTY', 'direction' => 'bullish' }
    )
  end
  let(:position_data) do
    Positions::ActiveCache::PositionData.new(
      tracker_id: tracker.id,
      security_id: tracker.security_id,
      segment: tracker.segment,
      entry_price: tracker.entry_price,
      quantity: tracker.quantity,
      current_ltp: 110.0,
      pnl: 250.0,
      pnl_pct: 0.10,
      peak_profit_pct: 0.10,
      position_direction: :bullish,
      index_key: 'NIFTY'
    )
  end

  before do
    allow(Positions::ActiveCache).to receive(:instance).and_return(active_cache)
    allow(active_cache).to receive_messages(get_by_tracker_id: position_data, all_positions: [position_data])
    allow(PositionTracker).to receive(:active).and_return(PositionTracker.where(id: tracker.id))

    # Mock pnl_snapshot to return valid data
    allow(service).to receive(:pnl_snapshot).with(tracker).and_return({
      pnl: BigDecimal('250.0'),
      pnl_pct: BigDecimal('0.10'),
      ltp: BigDecimal('110.0'),
      hwm_pnl: BigDecimal('250.0')
    })

    # Stub MarketFeedHub globally to prevent WebSocket subscription errors
    allow(Live::MarketFeedHub).to receive(:instance).and_return(
      instance_double(Live::MarketFeedHub, running?: true, connected?: true, subscribed?: true, stop!: true)
    )
  end

  describe '#enforce_structure_invalidation' do
    it 'exits when StructureInvalidationRule triggers' do
      # Stub RuleResult
      result = instance_double(Risk::Rules::RuleResult, exit?: true, reason: 'STRUCTURE_INVALIDATION')

      # Stub StructureInvalidationRule to return exit result
      allow_any_instance_of(Risk::Rules::StructureInvalidationRule).to receive(:evaluate).and_return(result)

      expect(exit_engine).to receive(:execute_exit).with(tracker, /STRUCTURE_INVALIDATION/)

      service.send(:enforce_structure_invalidation, exit_engine: exit_engine)
    end

    it 'does not exit when StructureInvalidationRule does not trigger' do
      # Stub RuleResult
      result = instance_double(Risk::Rules::RuleResult, exit?: false)

      # Stub StructureInvalidationRule to return no-exit result
      allow_any_instance_of(Risk::Rules::StructureInvalidationRule).to receive(:evaluate).and_return(result)

      expect(exit_engine).not_to receive(:execute_exit)

      service.send(:enforce_structure_invalidation, exit_engine: exit_engine)
    end
  end

  describe 'Peak Drawdown Gating (via TrailingEngine)' do
    before do
      # Mock TrailingEngine
      @trailing_engine = instance_double(Live::TrailingEngine)
      service.instance_variable_set(:@trailing_engine, @trailing_engine)

      # Ensure trade_state is set so enforce_dynamic_trailing_stops_for doesn't return early
      tracker.update!(trade_state: 'expansion')
    end

    it 'delegates to TrailingEngine' do
      expect(@trailing_engine).to receive(:process_tick).with(position_data, exit_engine: exit_engine).and_return({ exit_triggered: false })

      service.send(:enforce_dynamic_trailing_stops, exit_engine: exit_engine)
    end

    it 'logs when TrailingEngine triggers exit' do
      allow(@trailing_engine).to receive(:process_tick).and_return({ exit_triggered: true, reason: 'peak drawdown' })
      allow(Rails.logger).to receive(:info)

      service.send(:enforce_dynamic_trailing_stops, exit_engine: exit_engine)

      expect(Rails.logger).to have_received(:info).with(match(/TrailingEngine triggered exit/))
    end
  end
end
