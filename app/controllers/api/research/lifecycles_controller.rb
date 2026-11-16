# frozen_string_literal: true

module Api
  module Research
    # Read surface for Research::PremiumLifecycle — powers the dashboard's Research page
    # "Premium Lifecycle Board" panel; `show` also returns the option bars for charting.
    # Building a board is LifecycleRunsController.
    class LifecyclesController < ApplicationController
      include Api::TokenAuthenticatable
      include Api::Research::Paginatable
      include Api::Research::LifecycleSerialization

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

      private

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
    end
  end
end
