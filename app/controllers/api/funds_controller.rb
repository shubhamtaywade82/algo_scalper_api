# frozen_string_literal: true

module Api
  class FundsController < ApplicationController
    include Api::TokenAuthenticatable

    before_action :authenticate_dashboard_token!

    def index
      paper_mode = begin
        AlgoConfig.fetch.dig(:paper_trading, :enabled) == true
      rescue StandardError
        false
      end

      if paper_mode
        begin
          Ledger::Seeder.ensure_ready!
          snapshot = Ledger::WalletReader.snapshot(mode: :paper)
          render json: {
            cash: snapshot[:cash].to_f,
            equity: snapshot[:equity].to_f,
            mtm: snapshot[:mtm].to_f,
            exposure: snapshot[:exposure].to_f,
            margin_used: snapshot[:utilized].to_f
          }
        rescue StandardError => e
          Rails.logger.error("[Api::FundsController] Ledger snapshot error: #{e.message}")
          render json: { cash: 0.0, equity: 0.0, mtm: 0.0, exposure: 0.0, margin_used: 0.0 }
        end
      else
        begin
          funds = DhanHQ::Models::Funds.fetch
          # Calculate active MTM from live position trackers if any
          mtm = begin
            Positions::ActivePositionsCache.instance.active_trackers.sum { |t| t.unrealized_pnl.to_f }
          rescue StandardError
            0.0
          end

          render json: {
            cash: funds.available_balance.to_f,
            equity: funds.sod_limit.to_f,
            mtm: mtm,
            exposure: (funds.collateral_amount.to_f + funds.receiveable_amount.to_f),
            margin_used: funds.utilized_amount.to_f
          }
        rescue StandardError => e
          Rails.logger.error("[Api::FundsController] Error fetching live funds: #{e.message}")
          render json: { cash: 0.0, equity: 0.0, mtm: 0.0, exposure: 0.0, margin_used: 0.0, error: e.message }
        end
      end
    end
  end
end
