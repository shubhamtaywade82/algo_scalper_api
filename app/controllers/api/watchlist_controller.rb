# frozen_string_literal: true

module Api
  class WatchlistController < ApplicationController
    # GET /api/watchlist
    def index
      items = WatchlistItem.active.includes(:watchable).order(created_at: :desc)

      render json: {
        success: true,
        data: items.map { |item| format_watchlist_item(item) }
      }
    rescue StandardError => e
      Rails.logger.error("[Api::WatchlistController] Error fetching watchlist: #{e.class} - #{e.message}")
      render json: { success: false, error: 'Failed to fetch watchlist' }, status: :internal_server_error
    end

    # POST /api/watchlist
    def create
      item = WatchlistItem.new(watchlist_item_params)

      if item.save
        render json: {
          success: true,
          data: format_watchlist_item(item)
        }, status: :created
      else
        render json: {
          success: false,
          errors: item.errors.full_messages
        }, status: :unprocessable_entity
      end
    rescue StandardError => e
      Rails.logger.error("[Api::WatchlistController] Error creating watchlist item: #{e.class} - #{e.message}")
      render json: { success: false, error: 'Failed to create watchlist item' }, status: :internal_server_error
    end

    # DELETE /api/watchlist/:id
    def destroy
      item = WatchlistItem.find(params[:id])

      if item.update(active: false)
        render json: { success: true, message: 'Watchlist item removed' }
      else
        render json: {
          success: false,
          errors: item.errors.full_messages
        }, status: :unprocessable_entity
      end
    rescue ActiveRecord::RecordNotFound
      render json: { success: false, error: 'Watchlist item not found' }, status: :not_found
    rescue StandardError => e
      Rails.logger.error("[Api::WatchlistController] Error removing watchlist item: #{e.class} - #{e.message}")
      render json: { success: false, error: 'Failed to remove watchlist item' }, status: :internal_server_error
    end

    # GET /api/watchlist/:id
    def show
      item = WatchlistItem.find(params[:id])

      render json: {
        success: true,
        data: format_watchlist_item(item, include_recommendations: true)
      }
    rescue ActiveRecord::RecordNotFound
      render json: { success: false, error: 'Watchlist item not found' }, status: :not_found
    rescue StandardError => e
      Rails.logger.error("[Api::WatchlistController] Error fetching watchlist item: #{e.class} - #{e.message}")
      render json: { success: false, error: 'Failed to fetch watchlist item' }, status: :internal_server_error
    end

    private

    def watchlist_item_params
      params.require(:watchlist_item).permit(
        :segment,
        :security_id,
        :kind,
        :label,
        :watchable_type,
        :watchable_id
      )
    end

    def format_watchlist_item(item, include_recommendations: false)
      data = {
        id: item.id,
        segment: item.segment,
        security_id: item.security_id,
        kind: item.kind,
        label: item.label,
        active: item.active,
        created_at: item.created_at,
        updated_at: item.updated_at
      }

      if include_recommendations
        recommendations = SwingTradingRecommendation.active
                                                    .where(watchlist_item_id: item.id)
                                                    .order(analysis_timestamp: :desc)
                                                    .limit(10)

        data[:recommendations] = recommendations.map { |rec| format_recommendation(rec) }
      end

      data
    end

    def format_recommendation(rec)
      {
        id: rec.id,
        recommendation_type: rec.recommendation_type,
        direction: rec.direction,
        entry_price: rec.entry_price.to_f,
        stop_loss: rec.stop_loss.to_f,
        take_profit: rec.take_profit.to_f,
        quantity: rec.quantity,
        allocation_pct: rec.allocation_pct.to_f,
        hold_duration_days: rec.hold_duration_days,
        confidence_score: rec.confidence_score&.to_f,
        risk_reward_ratio: rec.risk_reward_ratio,
        investment_amount: rec.investment_amount,
        technical_analysis: rec.technical_analysis,
        volume_analysis: rec.volume_analysis,
        reasoning: rec.reasoning,
        analysis_timestamp: rec.analysis_timestamp,
        expires_at: rec.expires_at,
        created_at: rec.created_at
      }
    end
  end
end
