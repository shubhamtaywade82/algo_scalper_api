# frozen_string_literal: true

module Paper
  class EodRollup
    TIMEZONE = 'Asia/Kolkata'

    def call(now = Time.current)
      date = now.in_time_zone(TIMEZONE).to_date
      ns = "paper:#{date}"

      redis = Redis.new(url: ENV.fetch('REDIS_URL', 'redis://localhost:6379/0'))
      wallet = redis.hgetall("#{ns}:wallet")
      return unless wallet.present?

      opening = opening_cash_for(date) || wallet['cash'].to_f
      closing = wallet['cash'].to_f
      realized = wallet['realized_pnl'].to_f
      unrealized = wallet['unrealized_pnl'].to_f
      fees = wallet['fees_total'].to_f
      equity = wallet['equity'].to_f
      max_eq = wallet['max_equity'].to_f
      min_eq = wallet['min_equity'].to_f
      trades_count = PaperFillsLog.where(trading_date: date).count

      PaperDailyWallet.upsert(
        {
          trading_date: date,
          opening_cash: opening,
          closing_cash: closing,
          gross_pnl: (realized + unrealized),
          fees_total: fees,
          net_pnl: (realized + unrealized - fees),
          max_drawdown: (max_eq - min_eq).abs,
          max_equity: max_eq,
          min_equity: min_eq,
          trades_count: trades_count,
          meta: { paper_mode: true, equity: equity }
        },
        unique_by: :trading_date
      )
    end

    private

    def opening_cash_for(date)
      PaperDailyWallet.find_by(trading_date: date - 1)&.closing_cash
    end
  end
end


