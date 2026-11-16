# frozen_string_literal: true

module Api
  module Research
    # POST /api/research/lifecycle_runs — synchronously fetches the ATM+/-N board
    # (real DhanHQ calls) and persists ranked lifecycles via Research::LifecycleRunner.
    class LifecycleRunsController < ApplicationController
      include Api::TokenAuthenticatable
      include Api::Research::LifecycleSerialization

      before_action :authenticate_dashboard_token!

      def create
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
    end
  end
end
