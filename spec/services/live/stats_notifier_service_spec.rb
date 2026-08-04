# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Live::StatsNotifierService do
  let(:service) { described_class.instance }
  let!(:strategy_record) { Strategies::Record.create!(name: 'Supertrend V1', slug: 'supertrend_v1') }
  let!(:strategy_version) do
    Strategies::Version.create!(
      strategy_id: strategy_record.id,
      version: 1,
      file_path: 'foo',
      checksum: 'bar',
      manifest: { name: 'Supertrend V1' },
      scan_report: {},
      deployed_at: Time.current
    )
  end
  let!(:strategy_run) do
    Strategies::Run.create!(
      strategy_id: strategy_record.id,
      strategy_version_id: strategy_version.id,
      started_at: Time.current
    )
  end

  before do
    allow(Notifications::TelegramNotifier.instance).to receive(:enabled?).and_return(true)
    allow(Notifications::TelegramNotifier.instance).to receive(:send_message)

    allow(AlgoConfig).to receive(:fetch).and_return(
      telegram: {
        enabled: true,
        notify_no_trade_sessions: true
      }
    )
  end

  describe '#handle_regime_transition' do
    let(:start_time) { Time.zone.parse('11:30') }
    let(:end_time) { Time.zone.parse('13:45') }
    let(:regime_cfg) { { start: '11:30', end: '13:45' } }

    before do
      allow(Live::TimeRegimeService.instance).to receive(:regime_config).with(:chop_decay).and_return(regime_cfg)
    end

    context 'when trades were executed in the previous session' do
      it 'does not send a telegram notification' do
        allow(PositionTracker).to receive(:where).with(created_at: start_time..end_time).and_return(double(count: 1))

        service.send(:handle_regime_transition, :chop_decay, :close_gamma)
        expect(Notifications::TelegramNotifier.instance).not_to have_received(:send_message)
      end
    end

    context 'when no trades were executed in the previous session' do
      before do
        allow(PositionTracker).to receive(:where).with(created_at: start_time..end_time).and_return(double(count: 0))
      end

      it 'sends a telegram notification when there are no signals' do
        allow(Strategies::Signal).to receive(:where).with(created_at: start_time..end_time).and_return(Strategies::Signal.none)

        service.send(:handle_regime_transition, :chop_decay, :close_gamma)
        expect(Notifications::TelegramNotifier.instance).to have_received(:send_message).with(
          a_string_including("No Trades in Session: CHOP DECAY", "No strategy signals were generated")
        )
      end

      it 'sends a telegram notification with signal summary and top block reasons' do
        Strategies::Signal.delete_all

        [
          ['BANKNIFTY', 'hold', 'ignored_hold', 'adx_below_min(13.5)'],
          ['BANKNIFTY', 'buy_put', 'blocked_by_guard', 'supertrend_bearish_adx_43.3', { 'entry_result_reason' => 'time regime rules for BANKNIFTY' }],
          ['SENSEX', 'buy_put', 'blocked_by_guard', 'supertrend_bearish_adx_confirmed', { 'entry_result_reason' => 'time regime rules for SENSEX' }]
        ].each_with_index do |(inst, act, out, rsn, meta), i|
          Strategies::Signal.create!(
            strategy_id: strategy_record.id, strategy_version_id: strategy_version.id, strategy_run_id: strategy_run.id,
            instrument_key: inst, action: act, outcome: out, reason: rsn, metadata: meta || {},
            emitted_at: Time.current, created_at: start_time + ((i * 5) + 10).minutes
          )
        end

        service.send(:handle_regime_transition, :chop_decay, :close_gamma)
        expect(Notifications::TelegramNotifier.instance).to have_received(:send_message).with(
          a_string_including(
            "No Trades in Session: CHOP DECAY",
            "Total Signals:</b> 3",
            "Filtered (Holds):</b> 1",
            "Blocked by Guards:</b> 2",
            "time regime rules for BANKNIFTY: 1 times",
            "time regime rules for SENSEX: 1 times"
          )
        )
      end
    end
  end
end
