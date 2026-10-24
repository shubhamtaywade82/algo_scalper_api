# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Entries::EntryGuard do
  describe '.try_enter concurrency' do
    it 'serializes two concurrent try_enter calls for the same index key' do
      index_cfg = { key: 'NIFTY', segment: 'NSE_FNO', max_same_side: 1, cooldown_sec: 0 }
      acquisitions = Queue.new

      # try_enter's guard chain uses `return false` throughout (a non-local return
      # from inside the AdvisoryLock block), which unwinds straight past any code
      # placed after `block.call` in a wrapper - so we can't observe an "exit"
      # marker here. Acquisition timing is enough to prove serialization: if the
      # lock works, t2's acquisition can't happen until t1's real Postgres
      # advisory lock is released, which happens only after t1's sleep(0.05).
      allow(Entries::AdvisoryLock).to receive(:with_index_lock).and_wrap_original do |original, key, &block|
        original.call(key) do
          acquisitions << [key, Time.now]
          block.call
        end
      end

      allow(Risk::CircuitBreaker.instance).to receive(:tripped?) do
        sleep 0.05
        true # blocks every entry - we only care about lock acquisition timing
      end

      t1 = Thread.new do
        described_class.try_enter(index_cfg: index_cfg, pick: { symbol: 'NIFTY24JAN20000CE' }, direction: :bullish)
      end
      sleep 0.01 # ensure t1 enters the lock first
      t2 = Thread.new do
        described_class.try_enter(index_cfg: index_cfg, pick: { symbol: 'NIFTY24JAN20000CE' }, direction: :bullish)
      end
      t1.join
      t2.join

      events = []
      events << acquisitions.pop until acquisitions.empty?

      expect(events.size).to eq(2)
      expect(events.map(&:first)).to eq(%w[NIFTY NIFTY])
      first_at, second_at = events.map(&:last)
      expect(second_at - first_at).to be >= 0.04 # t2 waited out t1's sleep(0.05)
    end
  end
end
