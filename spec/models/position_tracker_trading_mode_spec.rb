# frozen_string_literal: true

require 'rails_helper'

# TradingMode: the canonical paper/live discriminator, kept in lockstep with
# the legacy `paper` boolean (architecture review 2026-09).
RSpec.describe PositionTracker do
  describe 'trading mode sync' do
    it 'defaults to live' do
      tracker = create(:position_tracker)

      expect(tracker.trading_mode).to eq('live')
      expect(tracker).to be_live
      expect(tracker).not_to be_paper
      expect(tracker.paper).to be(false)
    end

    it 'derives trading_mode when the legacy paper boolean is written' do
      tracker = create(:position_tracker, paper: true)

      expect(tracker.trading_mode).to eq('paper')
      expect(tracker.paper).to be(true)
      expect(tracker).to be_paper
    end

    it 'mirrors the paper boolean when trading_mode is written' do
      tracker = create(:position_tracker, trading_mode: 'paper')

      expect(tracker.paper).to be(true)
      expect(tracker.trading_mode).to eq('paper')
    end

    it 'keeps both sides consistent on update' do
      tracker = create(:position_tracker, paper: true)

      tracker.update!(paper: false)

      expect(tracker.reload.trading_mode).to eq('live')

      tracker.update!(trading_mode: 'paper')

      expect(tracker.reload.paper).to be(true)
    end

    it 'scopes by mode without colliding with the legacy boolean scopes' do
      create(:position_tracker, paper: true)
      create(:position_tracker)

      expect(described_class.mode_paper.count).to eq(1)
      expect(described_class.mode_live.count).to eq(1)
      expect(described_class.paper.count).to eq(1)
      expect(described_class.live.count).to eq(1)
    end
  end

  describe 'executions association' do
    it 'collects first-class fill records for the position' do
      tracker = create(:position_tracker, paper: true)
      create(:execution, position_tracker: tracker, instrument: tracker.instrument)

      expect(tracker.executions.count).to eq(1)
    end
  end
end
