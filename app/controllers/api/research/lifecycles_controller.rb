# frozen_string_literal: true

module Api
  module Research
    # Read/run surface for Research::PremiumLifecycle — powers the dashboard's
    # Research page "Premium Lifecycle Board" panel. `run` synchronously
    # fetches the full ATM+/-N board (real DhanHQ calls) and persists ranked
    # lifecycles via Research::LifecycleRunner; `show` additionally returns
    # the underlying option bars for charting.
    class LifecyclesController < ApplicationController
      include Api::TokenAuthenticatable
      include Api::Research::Paginatable

      before_action :authenticate_dashboard_token!

      def index
        scope = ::Research::PremiumLifecycle.order(entry_ts: :desc)
        scope = scope.where(underlying_symbol: params[:underlying_symbol].to_s.upcase) if params[:underlying_symbol].present?
        scope = scope.where(expiry_flag: params[:expiry_flag]) if params[:expiry_flag].present?
        scope = scope.where(option_type: params[:option_type]) if params[:option_type].present?
        if params[:date].present?
          date = parse_date(params[:date])
          scope = scope.where(entry_ts: date.all_day) if date
        end

        records, meta = paginate(scope)
        render json: { lifecycles: records.map { |lifecycle| serialize_lifecycle(lifecycle) }, meta: meta }
      end

      def show
        lifecycle = ::Research::PremiumLifecycle.find(params.expect(:id))
        render json: { lifecycle: serialize_lifecycle(lifecycle), bars: serialize_bars(lifecycle) }
      rescue ActiveRecord::RecordNotFound
        render json: { error: "not_found" }, status: :not_found
      end

      def run
        symbol = params.require(:underlying_symbol)
        date = Date.parse(params.require(:date))
        spot = params.require(:spot_price).to_f
        raise ArgumentError, "spot_price must be > 0" if spot <= 0

        expiry_flag = params[:expiry_flag].presence || "WEEK"
        max_distance = (params[:max_distance] || 5).to_i.clamp(0, 10)
        entry_time = params[:entry_time].presence || "09:15"
        entry_ts = Time.zone.parse("#{date} #{entry_time}")
        raise ArgumentError, "invalid entry_time: #{entry_time}" if entry_ts.nil?

        lifecycles = ::Research::LifecycleRunner.run(
          symbol: symbol, spot: spot, expiry_flag: expiry_flag, entry_ts: entry_ts,
          from_date: date.strftime("%Y-%m-%d"), to_date: (date + 1).strftime("%Y-%m-%d"),
          max_distance: max_distance
        )

        render json: { lifecycles: lifecycles.map { |lifecycle| serialize_lifecycle(lifecycle) } }
      rescue ActionController::ParameterMissing, ArgumentError, Date::Error => e
        render json: { error: e.message }, status: :unprocessable_content
      end

      # Context -> Expectancy report: groups persisted lifecycles by a subset
      # of their entry-time regime labels and computes avg return / win rate /
      # avg time-to-peak / avg drawdown per bucket.
      def expectancy
        scope = expectancy_scope
        dimensions = params[:dimensions].presence&.split(",")&.map(&:strip) || ::Research::ExpectancyReport::DEFAULT_DIMENSIONS
        phase = params[:phase].presence || "entry"

        buckets = ::Research::ExpectancyReport.call(scope: scope, dimensions: dimensions, phase: phase)
        render json: { buckets: buckets, dimensions: dimensions, phase: phase, total_lifecycles: scope.count }
      rescue ArgumentError => e
        render json: { error: e.message }, status: :unprocessable_content
      end

      private

      def expectancy_scope
        scope = ::Research::PremiumLifecycle.where(status: "computed")
        scope = scope.where(underlying_symbol: params[:underlying_symbol].to_s.upcase) if params[:underlying_symbol].present?
        scope = scope.where(expiry_flag: params[:expiry_flag]) if params[:expiry_flag].present?
        scope = scope.where(option_type: params[:option_type]) if params[:option_type].present?
        if params[:date_from].present?
          from = parse_date(params[:date_from])
          scope = scope.where(entry_ts: from.beginning_of_day..) if from
        end
        if params[:date_to].present?
          to = parse_date(params[:date_to])
          scope = scope.where(entry_ts: ..to.end_of_day) if to
        end
        scope
      end

      def parse_date(str)
        Date.parse(str.to_s)
      rescue ArgumentError, TypeError
        nil
      end

      def serialize_bars(lifecycle)
        window_end = lifecycle.end_ts || (lifecycle.entry_ts + 1.day)
        ::Research::OptionBar
          .where(underlying_symbol: lifecycle.underlying_symbol, expiry_flag: lifecycle.expiry_flag,
                 option_type: lifecycle.option_type, strike_label: lifecycle.strike_label,
                 interval: lifecycle.interval, ts: lifecycle.entry_ts..window_end)
          .order(:ts)
          .map do |bar|
            {
              time: bar.ts.to_i, open: bar.open.to_f, high: bar.high.to_f, low: bar.low.to_f,
              close: bar.close.to_f, volume: bar.volume.to_i, oi: bar.oi.to_i
            }
          end
      end

      def serialize_lifecycle(lifecycle)
        {
          id: lifecycle.id,
          underlying_symbol: lifecycle.underlying_symbol,
          expiry_flag: lifecycle.expiry_flag,
          option_type: lifecycle.option_type,
          strike_label: lifecycle.strike_label,
          actual_strike: lifecycle.actual_strike&.to_f,
          interval: lifecycle.interval,
          status: lifecycle.status,
          entry_ts: lifecycle.entry_ts&.iso8601,
          entry_premium: lifecycle.entry_premium&.to_f,
          peak_ts: lifecycle.peak_ts&.iso8601,
          peak_premium: lifecycle.peak_premium&.to_f,
          peak_return_pct: lifecycle.peak_return_pct&.to_f,
          minutes_to_peak: lifecycle.minutes_to_peak,
          peak_duration_minutes: lifecycle.peak_duration_minutes,
          decay_start_ts: lifecycle.decay_start_ts&.iso8601,
          end_ts: lifecycle.end_ts&.iso8601,
          end_premium: lifecycle.end_premium&.to_f,
          end_return_pct: lifecycle.end_return_pct&.to_f,
          max_drawdown_after_peak_pct: lifecycle.max_drawdown_after_peak_pct&.to_f,
          threshold_minutes: lifecycle.threshold_minutes,
          underlying_context: lifecycle.underlying_context
        }
      end
    end
  end
end
