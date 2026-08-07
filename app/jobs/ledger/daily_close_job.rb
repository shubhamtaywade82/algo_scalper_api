# frozen_string_literal: true

module Ledger
  class DailyCloseJob < ApplicationJob
    queue_as :background

    def perform(trading_date: Time.zone.today, mode: :paper)
      mode = mode.to_s
      return if mode == 'paper' && !(Config.enabled? || Config.shadow_mode?)

      row = PaperDailyWallet.find_or_initialize_by(trading_date: trading_date, mode: mode)

      if mode == 'live'
        assign_live_attributes!(row, trading_date)
      else
        assign_paper_attributes!(row, trading_date)
      end

      row.save!
    rescue StandardError => e
      Rails.logger.error("[Ledger::DailyCloseJob] #{e.class} - #{e.message}")
    end

    private

    def assign_paper_attributes!(row, trading_date)
      snapshot = WalletReader.snapshot(mode: :paper)
      trades = PositionTracker.paper.where(exited_at: trading_date.all_day)

      row.assign_attributes(
        opening_cash: row.opening_cash.presence || snapshot[:cash],
        closing_cash: snapshot[:cash],
        gross_pnl: snapshot[:realized_pnl],
        net_pnl: snapshot[:realized_pnl] - snapshot[:brokerage_expense],
        fees_total: snapshot[:brokerage_expense],
        trades_count: trades.count,
        meta: { source: 'ledger_daily_close', equity: snapshot[:equity], mtm: snapshot[:mtm] }.merge(kpi_meta(trades))
      )
    end

    # No live capital-wallet ledger exists (Ledger::WalletReader's cash/realized_pnl/
    # brokerage_expense accounts are paper-only — its `mode:` param only affects the
    # unrealized/mtm component, not those), so live KPIs are derived directly from
    # PositionTracker rather than routed through the paper-oriented wallet snapshot.
    # opening_cash/closing_cash/max_equity/min_equity/max_drawdown stay at their column
    # defaults for live rows — there's no equivalent capital-curve concept to fill them with yet.
    def assign_live_attributes!(row, trading_date)
      trades = PositionTracker.live.where(exited_at: trading_date.all_day)
      gross_pnl = trades.sum(:last_pnl_rupees) || BigDecimal(0)
      fees_total = trades.sum(:charges_rupees) || BigDecimal(0)

      row.assign_attributes(
        gross_pnl: gross_pnl,
        net_pnl: gross_pnl - fees_total,
        fees_total: fees_total,
        trades_count: trades.count,
        meta: { source: 'live_position_trackers' }.merge(kpi_meta(trades))
      )
    end

    # Mirrors Api::ReportsController#performance's win_rate/profit_factor/expectancy
    # formulas. Duplicated here rather than extracted to a shared service, to avoid
    # restructuring that controller for an unrelated change.
    def kpi_meta(trades)
      total = trades.count
      wins = trades.where('last_pnl_rupees > 0').count
      losses = trades.where('last_pnl_rupees <= 0').count
      win_rate = total.positive? ? (wins.to_f / total * 100).round(2) : 0.0

      net = trades.sum(:last_pnl_rupees).to_f
      avg_win = wins.positive? ? (trades.where('last_pnl_rupees > 0').sum(:last_pnl_rupees).to_f / wins).round(2) : 0.0
      avg_loss = losses.positive? ? (trades.where('last_pnl_rupees <= 0').sum(:last_pnl_rupees).to_f / losses).round(2) : 0.0
      profit_factor = avg_loss.negative? ? (avg_win / avg_loss.abs).round(2) : 0.0

      {
        win_rate_percent: win_rate,
        profit_factor: profit_factor,
        expectancy: total.positive? ? (net / total).round(2) : 0.0
      }
    end
  end
end
