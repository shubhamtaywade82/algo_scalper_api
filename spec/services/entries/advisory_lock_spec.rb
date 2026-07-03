# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Entries::AdvisoryLock do
  describe '.with_index_lock' do
    it 'yields and returns the block result' do
      result = described_class.with_index_lock('NIFTY') { 42 }
      expect(result).to eq(42)
    end

    it 'releases the lock even when the block raises' do
      expect do
        described_class.with_index_lock('NIFTY') { raise 'boom' }
      end.to raise_error('boom')

      # A second acquisition on the same key must not deadlock if the first was released.
      result = described_class.with_index_lock('NIFTY') { :ok }
      expect(result).to eq(:ok)
    end

    it 'serializes concurrent callers on the same index key' do
      order = Queue.new
      t1 = Thread.new do
        described_class.with_index_lock('BANKNIFTY') do
          order << :t1_start
          sleep 0.05
          order << :t1_end
        end
      end
      sleep 0.01 # ensure t1 acquires first
      t2 = Thread.new do
        described_class.with_index_lock('BANKNIFTY') do
          order << :t2_start
        end
      end
      t1.join
      t2.join

      sequence = []
      sequence << order.pop until order.empty?
      expect(sequence).to eq(%i[t1_start t1_end t2_start])
    end
  end

  describe '.lock_key' do
    it 'is deterministic for the same index key' do
      expect(described_class.lock_key('NIFTY')).to eq(described_class.lock_key('NIFTY'))
    end

    it 'differs across index keys (no trivial collision for common keys)' do
      expect(described_class.lock_key('NIFTY')).not_to eq(described_class.lock_key('BANKNIFTY'))
    end
  end
end
