# frozen_string_literal: true

module Api
  module Research
    class LifecycleExpectanciesController < ApplicationController
      include Api::TokenAuthenticatable

      before_action :authenticate_dashboard_token!

      # Context -> Expectancy report: groups persisted lifecycles by a subset
      # of their entry-time regime labels and computes avg return / win rate /
      # avg time-to-peak / avg drawdown per bucket.
      def show
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
    end
  end
end
