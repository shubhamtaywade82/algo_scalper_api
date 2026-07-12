# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Research::LifecycleRunner do
  def make_bars(option_type, strike_label, prices)
    base = Time.zone.parse('2026-07-10 09:15:00')
    prices.each_with_index.map do |price, i|
      Research::OptionBar.create!(
        underlying_symbol: 'NIFTY', exchange_segment: 'NSE_FNO', expiry_flag: 'WEEK', option_type: option_type,
        strike_label: strike_label, interval: '5', ts: base + (i * 5).minutes,
        open: price, high: price + 5, low: price - 5, close: price, actual_strike: 25_000
      )
    end
  end

  describe '.run' do
    before do
      board = {
        'CE' => { 'ATM' => make_bars('CE', 'ATM', [180, 250, 320, 280, 200]) },
        'PE' => { 'ATM' => make_bars('PE', 'ATM', [150, 140, 120, 100, 90]) }
      }
      allow(Research::BoardFetcher).to receive(:call).and_return(board)
      allow(Research::UnderlyingContextSnapshot).to receive(:at).and_return({})
    end

    it 'persists a lifecycle per contract and ranks them by peak_return_pct' do
      ranked = described_class.run(
        symbol: 'NIFTY', spot: 24_982, expiry_flag: 'WEEK', entry_ts: Time.zone.parse('2026-07-10 09:15:00'),
        from_date: '2026-07-10', to_date: '2026-07-11', max_distance: 0
      )

      expect(ranked.size).to eq(2)
      expect(ranked.all? { |lifecycle| lifecycle.persisted? }).to be true
      expect(ranked.first.status).to eq('computed')
      expect(ranked.first.peak_return_pct).to be >= ranked.last.peak_return_pct
      expect(Research::PremiumLifecycle.count).to eq(2)
    end

    it 'is idempotent for the same contract/entry_ts (upserts rather than duplicating)' do
      2.times do
        described_class.run(
          symbol: 'NIFTY', spot: 24_982, expiry_flag: 'WEEK', entry_ts: Time.zone.parse('2026-07-10 09:15:00'),
          from_date: '2026-07-10', to_date: '2026-07-11', max_distance: 0
        )
      end

      expect(Research::PremiumLifecycle.count).to eq(2)
    end

    it 'is idempotent even when the anchor entry_ts does not land exactly on a bar boundary' do
      anchor = Time.zone.parse('2026-07-10 09:14:30') # bars start at 09:15:00 — one second earlier

      2.times do
        described_class.run(
          symbol: 'NIFTY', spot: 24_982, expiry_flag: 'WEEK', entry_ts: anchor,
          from_date: '2026-07-10', to_date: '2026-07-11', max_distance: 0
        )
      end

      expect(Research::PremiumLifecycle.count).to eq(2)
      expect(Research::PremiumLifecycle.pluck(:entry_ts)).to all(eq(anchor))
    end

    it 'isolates a per-contract analysis failure instead of losing every other result in the board' do
      call_count = 0
      allow(Research::PremiumLifecycleAnalyzer).to receive(:analyze).and_wrap_original do |original, *args, **kwargs|
        call_count += 1
        raise 'boom' if call_count == 1

        original.call(*args, **kwargs)
      end

      ranked = described_class.run(
        symbol: 'NIFTY', spot: 24_982, expiry_flag: 'WEEK', entry_ts: Time.zone.parse('2026-07-10 09:15:00'),
        from_date: '2026-07-10', to_date: '2026-07-11', max_distance: 0
      )

      # The failed contract is still persisted (status: "failed") rather than
      # silently dropped — only an exception past that point (e.g. a save
      # failure) would remove it from the results entirely.
      expect(ranked.size).to eq(2)
      expect(Research::PremiumLifecycle.pluck(:status)).to contain_exactly('computed', 'failed')
    end
  end
end
