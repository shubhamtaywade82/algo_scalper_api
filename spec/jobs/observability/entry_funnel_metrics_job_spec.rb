# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Observability::EntryFunnelMetricsJob do
  let(:metrics_service) { instance_double(Observability::EntryFunnelMetrics) }
  let(:report) do
    {
      date: Time.zone.today.iso8601,
      summary: {
        breakout_arms: 2,
        signals_created: 5,
        entered: 1,
        guard_blocked: 3,
        signal_skipped: 1,
        positions_opened: 1,
        enter_rate_pct: 25.0
      },
      guard_blocks: { by_guard: { 'BreakoutReadyGuard' => 3 } },
      signal_skips: { by_code: { 'missing_atr' => 1 } }
    }
  end

  before do
    allow(Observability::EntryFunnelMetrics).to receive(:new).and_return(metrics_service)
    allow(metrics_service).to receive_messages(call: report, render: 'ENTRY FUNNEL METRICS')
  end

  it 'builds and logs the post-session funnel report' do
    described_class.new.perform

    expect(Observability::EntryFunnelMetrics).to have_received(:new).with(date: Time.zone.today)
    expect(metrics_service).to have_received(:call)
    expect(metrics_service).to have_received(:render)
  end

  context 'when telegram entry funnel notify is enabled' do
    before do
      allow(AlgoConfig).to receive(:fetch).and_return(
        telegram: { enabled: true, notify_entry_funnel_at_market_close: true }
      )
      notifier = instance_double(Notifications::TelegramNotifier, enabled?: true)
      allow(Notifications::TelegramNotifier).to receive(:instance).and_return(notifier)
      allow(notifier).to receive(:send_message)
    end

    it 'sends a condensed summary to Telegram' do
      notifier = Notifications::TelegramNotifier.instance

      described_class.new.perform

      expect(notifier).to have_received(:send_message).with(include('Entry Funnel'))
    end
  end

  context 'when telegram entry funnel notify is disabled' do
    before do
      allow(AlgoConfig).to receive(:fetch).and_return(
        telegram: { enabled: true, notify_entry_funnel_at_market_close: false }
      )
      notifier = instance_double(Notifications::TelegramNotifier, enabled?: true)
      allow(Notifications::TelegramNotifier).to receive(:instance).and_return(notifier)
      allow(notifier).to receive(:send_message)
    end

    it 'does not send Telegram' do
      described_class.new.perform

      expect(Notifications::TelegramNotifier.instance).not_to have_received(:send_message)
    end
  end
end
