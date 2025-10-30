# frozen_string_literal: true

module Api
  module Paper
    class StateController < ApplicationController
      before_action :ensure_paper_mode

      # GET /api/paper/wallet
      def wallet
        snapshot = Orders.config.wallet_snapshot
        render json: snapshot.transform_values { |v| v.respond_to?(:to_f) ? v.to_f : v }
      rescue StandardError => e
        Rails.logger.error("[Api::Paper::StateController] wallet failed: #{e.message}")
        render json: { error: 'Failed to fetch wallet snapshot' }, status: :internal_server_error
      end

      # GET /api/paper/position?seg=NSE_FNO&sid=50058
      def position
        seg = params[:seg] || params[:segment]
        sid = params[:sid] || params[:security_id]
        unless seg && sid
          render json: { error: 'Missing seg or sid parameter' }, status: :bad_request
          return
        end

        pos = Orders.config.position(segment: seg, security_id: sid)
        if pos
          render json: {
            segment: seg,
            security_id: sid,
            qty: pos[:qty],
            avg_price: pos[:avg_price].to_f,
            upnl: pos[:upnl].to_f,
            rpnl: pos[:rpnl].to_f,
            last_ltp: pos[:last_ltp].to_f
          }
        else
          render json: { segment: seg, security_id: sid, qty: 0, message: 'No active position' }
        end
      rescue StandardError => e
        Rails.logger.error("[Api::Paper::StateController] position failed: #{e.message}")
        render json: { error: 'Failed to fetch position' }, status: :internal_server_error
      end

      # GET /api/paper/fills?date=2025-10-30&limit=200
      def fills
        date = params[:date] || Paper::TradingClock.trading_date.to_s
        lim = params[:limit].to_i
        limit = lim.positive? ? [lim, 1000].min : 200
        logs = ::PaperFillsLog.where(trading_date: date).order(executed_at: :desc).limit(limit)
        render json: logs.as_json
      rescue StandardError => e
        Rails.logger.error("[Api::Paper::StateController] fills failed: #{e.message}")
        render json: { error: 'Failed to fetch fills' }, status: :internal_server_error
      end

      # GET /api/paper/performance?date=2025-10-30
      def performance
        date = params[:date]
        rec = if date
                ::PaperDailyWallet.find_by(trading_date: date)
              else
                ::PaperDailyWallet.order(trading_date: :desc).first
              end
        if rec
          render json: rec.as_json
        else
          render json: { message: 'No record' }, status: :not_found
        end
      rescue StandardError => e
        Rails.logger.error("[Api::Paper::StateController] performance failed: #{e.message}")
        render json: { error: 'Failed to fetch performance' }, status: :internal_server_error
      end

      private

      def ensure_paper_mode
        head :not_found unless ExecutionMode.paper?
      end
    end
  end
end


