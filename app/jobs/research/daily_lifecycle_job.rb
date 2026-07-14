# frozen_string_literal: true

module Research
  # Automates what a human previously had to click "Run Board" for: once a
  # trading day is over, runs Research::LifecycleRunner for one index against
  # the prior completed session, so research_premium_lifecycles accumulates
  # data without manual effort. Scheduled per-index in config/recurring.yml,
  # mirroring the existing AiTechnicalAnalysisJob("NIFTY")/("SENSEX") pattern.
  #
  # Runs the morning after the session (not right after close) — the exact
  # same-day intraday availability of DhanHQ::Models::ExpiredOptionsData for
  # a still-current (non-expired) contract is unverified, so this
  # deliberately targets "yesterday's" already-settled session instead of
  # risking an empty/partial fetch on the current cycle.
  class DailyLifecycleJob < ApplicationJob
    queue_as :background

    DEFAULT_MAX_DISTANCE = 5
    DEFAULT_ENTRY_TIME = "09:15"
    # Mirrors Options::ExpiredFetcher#normalize_expiry_flag's weekly/monthly
    # rule (NIFTY/SENSEX are weekly, BANKNIFTY is monthly-only). Duplicated
    # rather than called, on purpose — see Research::StrikeResolver's own
    # docstring for why Research:: stays isolated from the live
    # options/index_rules path.
    MONTHLY_ONLY_SYMBOLS = %w[BANKNIFTY].freeze

    def perform(index_key, max_distance: DEFAULT_MAX_DISTANCE, entry_time: DEFAULT_ENTRY_TIME)
      symbol = index_key.to_s.upcase
      session_date = Market::Calendar.trading_days_ago(1)
      return unless Market::Calendar.trading_day?(session_date)

      entry_ts = Time.zone.parse("#{session_date} #{entry_time}")
      spot = resolve_spot(symbol, entry_ts)
      return log_no_data(symbol, entry_ts) if spot.nil?

      Research::LifecycleRunner.run(
        symbol: symbol, spot: spot, expiry_flag: expiry_flag_for(symbol), entry_ts: entry_ts,
        from_date: session_date.strftime("%Y-%m-%d"), to_date: (session_date + 1).strftime("%Y-%m-%d"),
        max_distance: max_distance
      )
    rescue StandardError => e
      Rails.logger.error("[Research::DailyLifecycleJob] #{index_key} failed: #{e.class} - #{e.message}")
      Notifications::TelegramNotifier.instance.notify_error(
        "#{e.class} - #{e.message}", context: "Research::DailyLifecycleJob(#{index_key})"
      )
    end

    private

    def resolve_spot(symbol, entry_ts)
      Candles::Record
        .for_instrument(symbol)
        .for_timeframe("1m")
        .where("ts >= ?", entry_ts)
        .order(:ts)
        .first
        &.open
    end

    def expiry_flag_for(symbol)
      MONTHLY_ONLY_SYMBOLS.include?(symbol) ? "MONTH" : "WEEK"
    end

    def log_no_data(symbol, entry_ts)
      Rails.logger.warn("[Research::DailyLifecycleJob] no persisted candle at/after #{entry_ts} for #{symbol} — skipping")
      nil
    end
  end
end
