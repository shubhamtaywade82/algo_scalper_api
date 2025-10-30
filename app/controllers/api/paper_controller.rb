# frozen_string_literal: true

module Api
  class PaperController < ApplicationController
    before_action :check_paper_mode

    # GET /api/paper/wallet
    # Returns wallet snapshot (cash, equity, mtm, exposure)
    def wallet
      snapshot = Orders.config.wallet_snapshot
      render json: {
        cash: snapshot[:cash].to_f,
        equity: snapshot[:equity].to_f,
        mtm: snapshot[:mtm].to_f,
        exposure: snapshot[:exposure].to_f,
        timestamp: Time.current.to_i
      }
    rescue StandardError => e
      Rails.logger.error("[PaperController] wallet failed: #{e.message}")
      render json: { error: 'Failed to fetch wallet snapshot' }, status: :internal_server_error
    end

    # GET /api/paper/position?segment=NSE_FNO&security_id=12345
    # Returns position snapshot for a specific instrument
    def position
      segment = params[:segment] || params[:seg]
      security_id = params[:security_id] || params[:sid]

      unless segment && security_id
        render json: { error: 'Missing segment or security_id parameter' }, status: :bad_request
        return
      end

      pos = Orders.config.position(segment: segment, security_id: security_id)
      if pos
        render json: {
          segment: pos[:segment] || segment,
          security_id: pos[:security_id] || security_id,
          qty: pos[:qty],
          avg_price: pos[:avg_price].to_f,
          upnl: pos[:upnl].to_f,
          rpnl: pos[:rpnl].to_f,
          last_ltp: pos[:last_ltp].to_f,
          updated_at: pos[:updated_at],
          timestamp: Time.current.to_i
        }
      else
        render json: {
          segment: segment,
          security_id: security_id,
          qty: 0,
          message: 'No active position'
        }
      end
    rescue StandardError => e
      Rails.logger.error("[PaperController] position failed: #{e.message}")
      render json: { error: 'Failed to fetch position' }, status: :internal_server_error
    end

    # GET /api/paper/orders?limit=100
    # Returns recent order logs (if available)
    def orders
      limit_param = params[:limit].to_i
      limit = limit_param.positive? ? [limit_param, 1000].min : 100

      unless ExecutionMode.paper? && Orders.config.respond_to?(:order_logs)
        render json: { error: 'Order logs not available' }, status: :not_implemented
        return
      end

      logs = Orders.config.order_logs(limit: limit)
      render json: { count: logs.size, logs: logs }
    rescue StandardError => e
      Rails.logger.error("[PaperController] orders failed: #{e.message}")
      render json: { error: 'Failed to fetch orders' }, status: :internal_server_error
    end

    private

    def check_paper_mode
      return if ExecutionMode.paper?

      render json: { error: 'Paper mode not enabled' }, status: :not_found
    end
  end
end
