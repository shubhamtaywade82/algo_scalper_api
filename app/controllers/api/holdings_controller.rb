# frozen_string_literal: true

module Api
  class HoldingsController < ApplicationController
    include Api::TokenAuthenticatable

    before_action :authenticate_dashboard_token!

    def index
      paper_mode = begin
        AlgoConfig.fetch.dig(:paper_trading, :enabled) == true
      rescue StandardError
        false
      end

      if paper_mode
        # Simulating a default mock paper holding for demonstration/testing in paper mode
        mock_holdings = [
          {
            symbol: "TATASTEEL",
            quantity: 100,
            avg_price: 150.50,
            ltp: 152.30,
            pnl: 180.00,
            segment: "NSE_EQ"
          },
          {
            symbol: "RELIANCE",
            quantity: 10,
            avg_price: 2450.00,
            ltp: 2435.00,
            pnl: -150.00,
            segment: "NSE_EQ"
          }
        ]
        render json: { success: true, holdings: mock_holdings }
      else
        begin
          holdings = DhanHQ::Models::Holding.all.map do |h|
            data = h.to_h
            {
              symbol: data[:trading_symbol],
              quantity: data[:total_qty],
              avg_price: data[:avg_cost_price],
              ltp: data[:avg_cost_price], # DhanHQ doesn't return LTP directly in holdings API, default to avg
              pnl: 0.0,
              segment: data[:exchange]
            }
          end
          render json: { success: true, holdings: holdings }
        rescue StandardError => e
          Rails.logger.error("[Api::HoldingsController] Error fetching holdings: #{e.message}")
          render json: { success: false, error: e.message, holdings: [] }
        end
      end
    end
  end
end
