# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Observability::EntryFunnelMetrics do
  let(:date) { Time.zone.today }

  before do
    OptionsBuyingSignalEvent.create!(
      index_key: 'nifty',
      event_type: 'breakout_armed_ce',
      occurred_at: date.in_time_zone.noon,
      metadata: { spot_ltp: 24_500.0 }
    )

    create(
      :trading_signal,
      :nifty_signal,
      :bullish,
      created_at: date.in_time_zone.noon,
      metadata: {
        'entry_outcome' => 'blocked',
        'entry_blocked_reason' => 'bullish breakout not armed for nifty'
      }
    )

    create(
      :trading_signal,
      :nifty_signal,
      :bullish,
      created_at: date.in_time_zone.noon + 5.minutes,
      metadata: {
        'entry_outcome' => 'skipped',
        'entry_skip_stage' => 'strike_selection',
        'entry_skip_code' => 'no_legs_after_filter'
      }
    )

    create(
      :trading_signal,
      :nifty_signal,
      :bullish,
      created_at: date.in_time_zone.noon + 10.minutes,
      metadata: { 'entry_outcome' => 'entered' }
    )
  end

  describe '.call' do
    subject(:result) { described_class.call(date: date, index_key: 'nifty') }

    it 'counts summary funnel totals' do
      expect(result[:summary][:breakout_arms]).to eq(1)
      expect(result[:summary][:signals_created]).to eq(3)
      expect(result[:summary][:entered]).to eq(1)
    end

    it 'groups guard blocks and signal skips' do
      expect(result[:guard_blocks][:by_guard]['BreakoutReadyGuard']).to eq(1)
      expect(result[:signal_skips][:by_code]['no_legs_after_filter']).to eq(1)
    end
  end

  describe '.guard_bucket_for' do
    it 'maps breakout block reasons to BreakoutReadyGuard' do
      reason = 'bearish breakout not armed for banknifty'
      expect(described_class.guard_bucket_for(reason)).to eq('BreakoutReadyGuard')
    end
  end

  describe '#render' do
    it 'includes summary and guard sections' do
      output = described_class.new(date: date).render

      expect(output).to include('ENTRY FUNNEL METRICS')
      expect(output).to include('GUARD BLOCKS')
      expect(output).to include('Pre-signal cycle blocks')
    end
  end
end
