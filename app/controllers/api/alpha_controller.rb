# frozen_string_literal: true

module Api
  class AlphaController < ApplicationController
    include Api::TokenAuthenticatable

    before_action :authenticate_dashboard_token!, only: %i[status scan history performance]
    before_action :authenticate_operator_token!, only: %i[execute]

    VALID_INDICES = %w[nifty banknifty sensex].freeze
    VALID_DIRECTIONS = %w[ce pe].freeze

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
    rescue StandardError => e
      Rails.logger.error("[AlphaController] status error: #{e.class} - #{e.message}")
      render json: { error: 'internal_error' }, status: :internal_server_error
    end

    # POST /api/alpha/scan
    def scan
      indices = (params[:indices] || VALID_INDICES).map(&:to_s) & VALID_INDICES
      indices = VALID_INDICES if indices.empty?

      engine = SignalEngine.new(indices: indices.map(&:to_sym))
      signals = engine.run

      render json: {
        signals: signals,
        count: signals.size,
        timestamp: Time.current.iso8601
      }
    rescue StandardError => e
      Rails.logger.error("[AlphaController] scan error: #{e.class} - #{e.message}")
      render json: { error: 'internal_error' }, status: :internal_server_error
    end

    # POST /api/alpha/execute
    def execute
      signal_params = params.require(:signal).permit(
        :index_key, :direction, :confidence, :strike, :expiry,
        :stop_loss, :target, :alpha_source, :timestamp, :expected_value
      ).to_h.symbolize_keys

      index_key = signal_params[:index_key].to_s.downcase
      direction = signal_params[:direction].to_s.downcase
      unless VALID_INDICES.include?(index_key)
        return render json: { status: :failure, reason: 'invalid index_key' }, status: :unprocessable_entity
      end
      unless VALID_DIRECTIONS.include?(direction)
        return render json: { status: :failure, reason: 'invalid direction' }, status: :unprocessable_entity
      end

      signal_params[:index_key] = index_key.to_sym
      signal_params[:direction] = direction.to_sym
      signal_params[:confidence] = signal_params[:confidence].to_f
      signal_params[:strike] = signal_params[:strike].to_f

      result = AlphaExecutionService.execute(signal_params)

      if result[:status] == :success
        render json: result
      else
        render json: result, status: :unprocessable_entity
      end
    rescue StandardError => e
      Rails.logger.error("[AlphaController] execute error: #{e.class} - #{e.message}")
      render json: { error: 'internal_error' }, status: :internal_server_error
    end

    # GET /api/alpha/history
    def history
      signals = AlphaSignal.recent.limit(100).to_a
      order_ids = signals.filter_map(&:order_id)
      trackers = PositionTracker.where(order_no: order_ids).index_by(&:order_no)

      data = signals.map do |s|
        row = s.as_json
        if s.order_id.present?
          tracker = trackers[s.order_id]
          row[:pnl] = tracker&.last_pnl_rupees || tracker&.current_pnl_rupees
          row[:symbol] = tracker&.symbol
          row[:qty] = tracker&.quantity
        end
        row
      end

      render json: data
    rescue StandardError => e
      Rails.logger.error("[AlphaController] history error: #{e.class} - #{e.message}")
      render json: { error: 'internal_error' }, status: :internal_server_error
    end

    # GET /api/alpha/performance
    def performance
      stats = AlphaSignal.executed.group(:alpha_source).count
      signals = AlphaSignal.executed.to_a
      trackers = PositionTracker.where(order_no: signals.filter_map(&:order_id)).index_by(&:order_no)

      pnl_stats = signals.group_by(&:alpha_source).transform_values do |sigs|
        relevant = sigs.filter_map { |s| trackers[s.order_id] }
        count = sigs.size
        total_pnl = relevant.sum { |t| t.last_pnl_rupees.to_f }
        wins = relevant.count { |t| t.last_pnl_rupees.to_f > 0 }

        {
          count: count,
          total_pnl: total_pnl.round(2),
          win_rate: count.positive? ? (wins.to_f / count * 100).round(1) : 0,
          avg_pnl: count.positive? ? (total_pnl / count).round(2) : 0
        }
      end

      render json: {
        by_source: pnl_stats,
        total_executed: stats.values.sum,
        timestamp: Time.current.iso8601
      }
    rescue StandardError => e
      Rails.logger.error("[AlphaController] performance error: #{e.class} - #{e.message}")
      render json: { error: 'internal_error' }, status: :internal_server_error
    end
  end
end
