# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Positions::Serializer do
  describe '.closed' do
    let(:tracker) do
      build_stubbed(
        :position_tracker,
        :exited,
        segment: 'NSE_FNO',
        entry_price: 100.0,
        exit_price: 102.0,
        quantity: 10,
        last_pnl_rupees: 20.0,
        exited_at: Time.zone.parse('2026-06-18 10:00:00 +05:30'),
        execution: { 'classified_as' => 'profit' },
        exit_reason: 'PROFIT_FLOOR_TICK (hwm: ₹350)',
        exit_path: 'profit_floor_tick'
      )
    end

    it 'includes exit_path for dashboard labeling' do
      payload = described_class.closed(tracker)

      expect(payload[:exit_path]).to eq('profit_floor_tick')
      expect(payload[:exit_reason]).to include('PROFIT_FLOOR_TICK')
      expect(payload[:exit_classification]).to eq('profit')
    end
  end

  describe '.detail' do
    context 'when the position is open' do
      let(:tracker) do
        create(:position_tracker,
               segment: 'NSE_FNO',
               iv_at_entry: 18.5, vix_at_entry: 13.2, dte_at_entry: 2,
               atm_strike: 25000, entry_underlying_price: 24980.5,
               entry_tf: '1m', alpha_source: 'supertrend_v1', entry_path: 'strategy_platform',
               signal_confidence: 0.7)
      end

      it 'includes base open fields plus entry context' do
        result = described_class.detail(tracker)

        expect(result[:id]).to eq(tracker.id)
        expect(result[:ltp]).to be_present # from base `open` serializer
        expect(result[:entry_context]).to eq(
          iv_at_entry: 18.5, vix_at_entry: 13.2, dte_at_entry: 2,
          atm_strike: 25000.0, expiry_date: nil,
          entry_underlying_price: 24980.5, entry_tf: '1m',
          alpha_source: 'supertrend_v1', entry_path: 'strategy_platform',
          signal_confidence: 0.7
        )
        expect(result[:exit_block]).to be_nil
      end

      it 'includes trailing/HWM state' do
        tracker.update!(hwm_pnl_pct: 0.18, secured_sl_price: BigDecimal('25100.0'),
                         breakeven_locked: true, profit_zone_state: 'tier_2')

        result = described_class.detail(tracker)
        expect(result[:trailing_state]).to eq(
          high_water_mark_pnl: tracker.high_water_mark_pnl.to_f,
          hwm_pnl_pct: 0.18,
          secured_sl_price: 25100.0,
          breakeven_locked: true,
          profit_zone_state: 'tier_2'
        )
      end

      it 'omits config_snapshot when no meta_snapshot exists' do
        result = described_class.detail(tracker)
        expect(result[:config_snapshot]).to be_nil
        expect(result[:config_version_hash]).to be_nil
      end

      it 'includes config_snapshot when a meta_snapshot exists' do
        tracker.create_meta_snapshot!(config_version_hash: 'abc123', config_snapshot: { risk: { max_loss: 500 } })

        result = described_class.detail(tracker)
        expect(result[:config_version_hash]).to eq('abc123')
        expect(result[:config_snapshot]).to eq(risk: { max_loss: 500 })
      end

      it 'includes the linked strategy signal and guard trail when present' do
        signal = create(:strategy_signal,
                         position_tracker: tracker,
                         action: 'buy_call',
                         confidence: 0.7,
                         outcome: 'executed',
                         reason: 'supertrend_bullish_adx_confirmed',
                         metadata: {
                           'entry_result_reason' => nil,
                           'guard_results' => [{ 'guard' => 'Entries::Guards::CooldownGuard', 'result' => 'pass' }]
                         })

        result = described_class.detail(tracker)
        expect(result[:strategy_signal]).to eq(
          strategy_slug: signal.strategy_record.slug,
          action: 'buy_call',
          confidence: 0.7,
          outcome: 'executed',
          reason: 'supertrend_bullish_adx_confirmed',
          entry_result_reason: nil,
          guard_results: [{ 'guard' => 'Entries::Guards::CooldownGuard', 'result' => 'pass' }]
        )
      end

      it 'sets strategy_signal to nil when no signal is linked' do
        result = described_class.detail(tracker)
        expect(result[:strategy_signal]).to be_nil
      end
    end

    context 'when the position is closed' do
      let(:tracker) do
        create(:position_tracker, :exited,
               segment: 'NSE_FNO',
               exit_price: BigDecimal('27500.00'),
               exit_reason: 'profit_target_hit',
               exit_path: 'unified_exit_checker',
               exited_at: Time.current,
               execution: { 'classified_as' => 'winner' })
      end

      it 'includes base closed fields plus the exit block' do
        result = described_class.detail(tracker)

        expect(result[:exit_price]).to eq(27500.0) # from base `closed` serializer
        expect(result[:exit_block]).to eq(
          exit_reason: 'profit_target_hit',
          exit_path: 'unified_exit_checker',
          exit_classification: 'winner',
          exited_at: tracker.exited_at.iso8601
        )
      end
    end
  end
end
