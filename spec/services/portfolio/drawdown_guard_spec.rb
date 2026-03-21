# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Portfolio::DrawdownGuard do
  let(:redis) { instance_double(Redis) }

  before do
    described_class.instance_variable_set(:@redis, redis)

    allow(redis).to receive(:get).and_return(nil)
    allow(redis).to receive(:set)
    allow(redis).to receive(:expire)
    allow(redis).to receive(:del)

    # Stub Telegram notifier
    telegram = instance_double(Notifications::TelegramNotifier, enabled?: false)
    allow(Notifications::TelegramNotifier).to receive(:instance).and_return(telegram)
  end

  after do
    described_class.instance_variable_set(:@redis, nil)
  end

  describe '.triggered?' do
    it 'returns false when the key is not set' do
      allow(redis).to receive(:get).with(described_class::KEY_TRIGGERED).and_return(nil)
      expect(described_class.triggered?).to be(false)
    end

    it 'returns true when the key is set to "true"' do
      allow(redis).to receive(:get).with(described_class::KEY_TRIGGERED).and_return('true')
      expect(described_class.triggered?).to be(true)
    end

    it 'returns false gracefully when Redis raises an error' do
      allow(redis).to receive(:get).and_raise(Redis::ConnectionError, 'down')
      expect(described_class.triggered?).to be(false)
    end
  end

  describe '.trigger_global_exit!' do
    let(:active_positions) { [] }

    before do
      active_cache = instance_double(Positions::ActiveCache, all_positions: active_positions)
      allow(Positions::ActiveCache).to receive(:instance).and_return(active_cache)
    end

    context 'when not yet triggered' do
      before do
        allow(redis).to receive(:get).with(described_class::KEY_TRIGGERED).and_return(nil)
      end

      it 'sets the triggered key' do
        expect(redis).to receive(:set).with(described_class::KEY_TRIGGERED, 'true')
        described_class.trigger_global_exit!(net_pnl: 5_000.0, floor: 6_000.0)
      end

      it 'sets the entries_blocked key' do
        allow(redis).to receive(:set).with(described_class::KEY_TRIGGERED, 'true')
        expect(redis).to receive(:set).with(described_class::KEY_ENTRIES_BLOCKED, 'true')
        described_class.trigger_global_exit!(net_pnl: 5_000.0, floor: 6_000.0)
      end

      context 'with active positions' do
        let(:pos_data)  { double('PositionData', tracker_id: 77) }
        let(:active_positions) { [pos_data] }
        let(:tracker)   { instance_double(PositionTracker, id: 77, active?: true) }
        let(:exit_engine) { instance_double(Live::ExitEngine) }

        before do
          allow(PositionTracker).to receive(:find_by).with(id: 77).and_return(tracker)
          allow(Live::ExitEngine).to receive(:instance).and_return(exit_engine)
          allow(exit_engine).to receive(:execute_exit)
        end

        it 'exits all active positions with PORTFOLIO_FLOOR_BREACH reason' do
          allow(redis).to receive(:set)
          expect(exit_engine).to receive(:execute_exit).with(tracker, 'PORTFOLIO_FLOOR_BREACH')
          described_class.trigger_global_exit!(net_pnl: 5_000.0, floor: 6_000.0)
        end
      end
    end

    context 'when already triggered (idempotency)' do
      before do
        allow(redis).to receive(:get).with(described_class::KEY_TRIGGERED).and_return('true')
      end

      it 'does not set the key again' do
        expect(redis).not_to receive(:set)
        described_class.trigger_global_exit!(net_pnl: 5_000.0, floor: 6_000.0)
      end
    end
  end

  describe '.entries_blocked?' do
    it 'returns false when key is not set' do
      allow(redis).to receive(:get).with(described_class::KEY_ENTRIES_BLOCKED).and_return(nil)
      expect(described_class.entries_blocked?).to be(false)
    end

    it 'returns true when key is set' do
      allow(redis).to receive(:get).with(described_class::KEY_ENTRIES_BLOCKED).and_return('true')
      expect(described_class.entries_blocked?).to be(true)
    end
  end

  describe '.reset_day!' do
    before do
      allow(Portfolio::PnlTracker).to receive(:reset_day!)
    end

    it 'deletes both guard keys' do
      expect(redis).to receive(:del).with(described_class::KEY_TRIGGERED)
      expect(redis).to receive(:del).with(described_class::KEY_ENTRIES_BLOCKED)
      described_class.reset_day!
    end

    it 'also resets PnlTracker state' do
      allow(redis).to receive(:del)
      expect(Portfolio::PnlTracker).to receive(:reset_day!)
      described_class.reset_day!
    end
  end
end
