# frozen_string_literal: true

module Api
  class AlphaController < ApplicationController
    # GET /api/alpha/status
    def status
      config = AlgoConfig.fetch[:alpha_strategies] || {}
      limits = AlgoConfig.fetch[:risk_limits] || {}
      
      render json: {
        enabled: config[:enabled] != false,
        indices: %w[nifty banknifty sensex],
        strategies: %w[momentum vol_expansion event gamma_scalp expiry],
        auto_execute_threshold: config[:auto_execute_threshold] || 0.75,
        risk_stats: Risk::LimitsGuard.current_stats,
        risk_limits: {
          daily_max_trades: limits[:daily_max_trades] || 10,
          max_consecutive_losses: limits[:max_consecutive_losses] || 3,
          max_open_positions: limits[:max_open_positions] || 3
        }
      }
    end

    # POST /api/alpha/scan
    def scan
      indices = (params[:indices] || %w[nifty banknifty sensex]).map(&:to_sym)
      engine = SignalEngine.new(indices: indices)
      signals = engine.run

      render json: {
        signals: signals,
        count: signals.size,
        timestamp: Time.current.iso8601
      }
    end

    # POST /api/alpha/execute
    def execute
      signal_params = params.require(:signal).permit!.to_h.symbolize_keys
      
      # Basic parameter normalization
      signal_params[:index_key] = signal_params[:index_key].to_sym
      signal_params[:direction] = signal_params[:direction].to_sym
      signal_params[:confidence] = signal_params[:confidence].to_f
      signal_params[:strike] = signal_params[:strike].to_f

      result = AlphaExecutionService.execute(signal_params)

      if result[:status] == :success
        render json: result
      else
        render json: result, status: :unprocessable_entity
      end
    end

    # GET /api/alpha/history
    def history
      signals = AlphaSignal.recent.limit(100).map do |s|
        data = s.as_json
        if s.order_id.present?
          tracker = PositionTracker.find_by(order_no: s.order_id)
          data[:pnl] = tracker&.last_pnl_rupees || tracker&.current_pnl_rupees
          data[:symbol] = tracker&.symbol
          data[:qty] = tracker&.quantity
        end
        data
      end
      render json: signals
    end

    # GET /api/alpha/performance
    def performance
      stats = AlphaSignal.executed.group(:alpha_source).count
      pnl_stats = {}

      stats.each do |source, count|
        signals = AlphaSignal.where(alpha_source: source).executed
        order_ids = signals.pluck(:order_id).compact
        trackers = PositionTracker.where(order_no: order_ids)
        
        total_pnl = trackers.sum(:last_pnl_rupees).to_f
        wins = trackers.where('last_pnl_rupees > 0').count
        
        pnl_stats[source] = {
          count: count,
          total_pnl: total_pnl.round(2),
          win_rate: count > 0 ? (wins.to_f / count * 100).round(1) : 0,
          avg_pnl: count > 0 ? (total_pnl / count).round(2) : 0
        }
      end

      render json: {
        by_source: pnl_stats,
        total_executed: stats.values.sum,
        timestamp: Time.current.iso8601
      }
    end
  end
end
