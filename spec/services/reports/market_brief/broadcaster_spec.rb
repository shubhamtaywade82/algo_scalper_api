# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Reports::MarketBrief::Broadcaster do
  let(:snapshot) { Reports::MarketBrief::SnapshotBuilder.call }
  let(:event) { { 'kind' => 'level_crossed', 'message' => 'NIFTY crossed LTF swing high 24,520.00 upward', 'ai_trigger' => true } }

  describe '.events' do
    it 'publishes one event frame carrying the events and the same payload the live endpoint returns' do
      expect(ActionCable.server).to receive(:broadcast).with(
        'market_brief',
        hash_including(type: 'event', events: [event], live: hash_including(live: true, mode: 'paper'))
      )

      described_class.events(snapshot: snapshot, mode: 'paper', events: [event])
    end

    it 'does not raise when the cable backend fails, so the watcher cycle keeps running' do
      allow(ActionCable.server).to receive(:broadcast).and_raise(StandardError, 'cable down')

      expect { described_class.events(snapshot: snapshot, mode: 'paper', events: [event]) }.not_to raise_error
    end
  end

  describe '.report' do
    it 'publishes a report frame for a finished report' do
      report, = MarketBriefReport.request!(mode: :paper)
      report.update!(status: 'ready', snapshot: snapshot, ai_status: 'unavailable', ai_error: 'no_response')

      expect(ActionCable.server).to receive(:broadcast).with(
        'market_brief',
        hash_including(type: 'report', report_id: report.id, live: hash_including(mode: 'paper'))
      )

      described_class.report(report)
    end

    it 'skips a report that has no snapshot yet' do
      report, = MarketBriefReport.request!(mode: :paper)
      expect(ActionCable.server).not_to receive(:broadcast)

      described_class.report(report)
    end
  end
end
