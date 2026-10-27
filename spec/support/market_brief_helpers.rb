# frozen_string_literal: true

# Shared stubs for the Market Brief specs. Only cross-process read boundaries
# (Redis tick cache, AnalysisStore, gates, heartbeats) are stubbed; signals,
# trackers and reconciliation rows go through the real database.
module MarketBriefHelpers
  BRIEF_INDICES = [
    { key: 'NIFTY', sid: '13', segment: 'IDX_I' },
    { key: 'BANKNIFTY', sid: '25', segment: 'IDX_I' },
    { key: 'SENSEX', sid: '51', segment: 'IDX_I' }
  ].freeze

  # 10:30 IST on a Tuesday — inside the cash session and the entry window.
  def brief_market_open_time
    Time.find_zone('Asia/Kolkata').local(2026, 10, 27, 10, 30, 0)
  end

  def brief_tick(ltp:, prev_close:, at: Time.current, security_id: '13')
    MarketTick.new(segment: 'IDX_I', security_id: security_id, ltp: BigDecimal(ltp.to_s), timestamp: at,
                   oi: 0, oi_change: 0, bid: nil, ask: nil, volume: 0, prev_close: prev_close)
  end

  def brief_regime_entry(label: 'TRENDING_UP', adx: 31.42, fresh: true)
    {
      data: { regime: label, confidence: adx,
              metrics: { adx_value: adx, atr_percent: 0.0042, volatility_regime: 'normal', bb_breakout: false } },
      validity: { computed_at: 1.minute.ago.iso8601, age_seconds: 60, fresh: fresh }
    }
  end

  def brief_smc_entry(decision: :call, trend: :bullish, fresh: true)
    frame = lambda do |interval|
      { interval: interval,
        context: { trend: trend, phase: :expansion,
                   swing_structure: { trend: trend, last_bos: { type: trend, price: 24_480.5, index: 42 },
                                      last_swing_high: { type: :high, price: 24_520.0, index: 40 },
                                      last_swing_low: { type: :low, price: 24_300.0, index: 30 } },
                   liquidity: { sweep: true, sweep_direction: :sell_side },
                   fvg: { active: [{ low: 1, high: 2 }] },
                   order_blocks: { active: [] },
                   premium_discount: { premium: false, discount: true } } }
    end
    {
      data: { decision: decision, timeframes: { htf: frame.call('60'), mtf: frame.call('15'), ltf: frame.call('5') } },
      validity: { computed_at: 2.minutes.ago.iso8601, age_seconds: 120, fresh: fresh }
    }
  end

  # rubocop:disable-next Metrics/AbcSize, Metrics/MethodLength
  def stub_market_brief_sources(quote_age: 2.seconds, regime: brief_regime_entry, smc: brief_smc_entry,
                                feed_alive: true, scheduler_alive: true, breaker_tripped: false,
                                vix: 13.25, vix_entry_allowed: true, daily_loss: 0.0, capital: 100_000.0)
    allow(IndexConfigLoader).to receive(:load_indices).and_return(BRIEF_INDICES.map(&:dup))
    allow(Market::Calendar).to receive(:trading_day?).and_return(true)
    allow(Live::TickQuery).to receive(:for_security) do |segment:, security_id:|
      next nil unless segment == 'IDX_I'

      brief_tick(ltp: 24_500.5, prev_close: 24_400.0, at: Time.current - quote_age, security_id: security_id)
    end
    allow(AnalysisStore).to receive(:read) { |_key, component| component == :regime ? regime : smc }

    allow(Market::VixGate).to receive_messages(current_ltp: vix, evaluated?: !vix.nil?, entry_allowed?: vix_entry_allowed,
                                               force_exit_active?: false)
    status_cache = Live::SystemStatusCache.instance
    allow(status_cache).to receive(:running?) do |name|
      { ws_market_feed: feed_alive, scheduler: scheduler_alive, ws_order_update: false }.fetch(name.to_sym, false)
    end
    allow(Risk::CircuitBreaker.instance).to receive(:status)
      .and_return(breaker_tripped ? { tripped: true, reason: 'manual', at: Time.current } : { tripped: false, reason: nil, at: nil })
    allow_any_instance_of(Live::DailyLimits).to receive(:get_global_daily_loss).and_return(daily_loss) # rubocop:disable RSpec/AnyInstance
    allow(Capital::Allocator).to receive(:available_cash).and_return(BigDecimal(capital.to_s))
  end

  def approved_signal(index_key: 'NIFTY', action: 'buy_call', emitted_at: Time.current, tracker: nil)
    create(:strategy_signal, instrument_key: index_key, action: action, outcome: 'executed',
                             emitted_at: emitted_at, position_tracker: tracker, reason: 'st_flip adx_28.4')
  end

  def blocked_signal(reason:, index_key: 'NIFTY', emitted_at: Time.current)
    create(:strategy_signal, instrument_key: index_key, action: 'buy_put', outcome: 'blocked_by_guard',
                             emitted_at: emitted_at, metadata: { 'entry_result_reason' => reason })
  end
end

RSpec.configure do |config|
  config.include MarketBriefHelpers
end
