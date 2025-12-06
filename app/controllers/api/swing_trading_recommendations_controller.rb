# frozen_string_literal: true

module Api
  class SwingTradingRecommendationsController < ApplicationController
    # GET /api/swing_trading/recommendations
    def index
      recommendations = SwingTradingRecommendation.active
                                                    .includes(:watchlist_item)
                                                    .order(analysis_timestamp: :desc)

      # Apply filters
      recommendations = recommendations.where(recommendation_type: params[:type]) if params[:type].present?
      recommendations = recommendations.where(direction: params[:direction]) if params[:direction].present?
      recommendations = recommendations.where(symbol_name: params[:symbol]) if params[:symbol].present?
      recommendations = recommendations.high_confidence(params[:min_confidence].to_f) if params[:min_confidence].present?

      # Pagination
      page = params[:page]&.to_i || 1
      per_page = [params[:per_page]&.to_i || 20, 100].min
      recommendations = recommendations.page(page).per(per_page)

      render json: {
        success: true,
        data: recommendations.map { |rec| format_recommendation(rec) },
        pagination: {
          page: page,
          per_page: per_page,
          total: recommendations.total_count,
          total_pages: recommendations.total_pages
        }
      }
    rescue StandardError => e
      Rails.logger.error("[Api::SwingTradingRecommendationsController] Error fetching recommendations: #{e.class} - #{e.message}")
      render json: { success: false, error: 'Failed to fetch recommendations' }, status: :internal_server_error
    end

    # GET /api/swing_trading/recommendations/:id
    def show
      recommendation = SwingTradingRecommendation.find(params[:id])

      render json: {
        success: true,
        data: format_recommendation(recommendation, detailed: true)
      }
    rescue ActiveRecord::RecordNotFound
      render json: { success: false, error: 'Recommendation not found' }, status: :not_found
    rescue StandardError => e
      Rails.logger.error("[Api::SwingTradingRecommendationsController] Error fetching recommendation: #{e.class} - #{e.message}")
      render json: { success: false, error: 'Failed to fetch recommendation' }, status: :internal_server_error
    end

    # POST /api/swing_trading/recommendations/:id/execute
    def execute
      recommendation = SwingTradingRecommendation.find(params[:id])

      if recommendation.status != 'active'
        render json: { success: false, error: 'Recommendation is not active' }, status: :unprocessable_entity
        return
      end

      if recommendation.update(status: :executed)
        render json: {
          success: true,
          message: 'Recommendation marked as executed',
          data: format_recommendation(recommendation)
        }
      else
        render json: {
          success: false,
          errors: recommendation.errors.full_messages
        }, status: :unprocessable_entity
      end
    rescue ActiveRecord::RecordNotFound
      render json: { success: false, error: 'Recommendation not found' }, status: :not_found
    rescue StandardError => e
      Rails.logger.error("[Api::SwingTradingRecommendationsController] Error executing recommendation: #{e.class} - #{e.message}")
      render json: { success: false, error: 'Failed to execute recommendation' }, status: :internal_server_error
    end

    # POST /api/swing_trading/recommendations/:id/cancel
    def cancel
      recommendation = SwingTradingRecommendation.find(params[:id])

      if recommendation.status != 'active'
        render json: { success: false, error: 'Only active recommendations can be cancelled' }, status: :unprocessable_entity
        return
      end

      if recommendation.update(status: :cancelled)
        render json: {
          success: true,
          message: 'Recommendation cancelled',
          data: format_recommendation(recommendation)
        }
      else
        render json: {
          success: false,
          errors: recommendation.errors.full_messages
        }, status: :unprocessable_entity
      end
    rescue ActiveRecord::RecordNotFound
      render json: { success: false, error: 'Recommendation not found' }, status: :not_found
    rescue StandardError => e
      Rails.logger.error("[Api::SwingTradingRecommendationsController] Error cancelling recommendation: #{e.class} - #{e.message}")
      render json: { success: false, error: 'Failed to cancel recommendation' }, status: :internal_server_error
    end

    # POST /api/swing_trading/recommendations/analyze/:watchlist_item_id
    def analyze
      watchlist_item = WatchlistItem.find(params[:watchlist_item_id])
      recommendation_type = params[:type] || 'swing'

      analyzer = SwingTrading::Analyzer.new(
        watchlist_item: watchlist_item,
        recommendation_type: recommendation_type
      )

      result = analyzer.call

      if result[:success]
        recommendation_data = result[:data]
        recommendation = SwingTradingRecommendation.create!(recommendation_data)

        render json: {
          success: true,
          message: 'Analysis completed',
          data: format_recommendation(recommendation, detailed: true)
        }, status: :created
      else
        render json: {
          success: false,
          error: result[:error]
        }, status: :unprocessable_entity
      end
    rescue ActiveRecord::RecordNotFound
      render json: { success: false, error: 'Watchlist item not found' }, status: :not_found
    rescue StandardError => e
      Rails.logger.error("[Api::SwingTradingRecommendationsController] Error analyzing: #{e.class} - #{e.message}")
      render json: { success: false, error: 'Analysis failed' }, status: :internal_server_error
    end

    private

    def format_recommendation(rec, detailed: false)
      data = {
        id: rec.id,
        watchlist_item_id: rec.watchlist_item_id,
        symbol_name: rec.symbol_name,
        segment: rec.segment,
        security_id: rec.security_id,
        recommendation_type: rec.recommendation_type,
        direction: rec.direction,
        entry_price: rec.entry_price.to_f,
        stop_loss: rec.stop_loss.to_f,
        take_profit: rec.take_profit.to_f,
        quantity: rec.quantity,
        allocation_pct: rec.allocation_pct.to_f,
        hold_duration_days: rec.hold_duration_days,
        confidence_score: rec.confidence_score&.to_f,
        status: rec.status,
        risk_reward_ratio: rec.risk_reward_ratio,
        investment_amount: rec.investment_amount,
        analysis_timestamp: rec.analysis_timestamp,
        expires_at: rec.expires_at,
        created_at: rec.created_at,
        updated_at: rec.updated_at
      }

      if detailed
        data[:technical_analysis] = rec.technical_analysis
        data[:volume_analysis] = rec.volume_analysis
        data[:reasoning] = rec.reasoning
        data[:technical_summary] = rec.technical_summary
        data[:volume_summary] = rec.volume_summary
      end

      data
    end
  end
end
