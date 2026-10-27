# frozen_string_literal: true

module Api
  # One-page Market Brief.
  #
  #   GET  /api/reports/market_brief        latest ready brief for the current mode (+ in-flight build, if any)
  #   GET  /api/reports/market_brief?id=42  a specific brief (used while polling a build)
  #   POST /api/reports/market_brief        request a build; returns 202 immediately
  #
  # Generation is asynchronous (Solid Queue) and deduplicated per 5-minute slot,
  # so repeated POSTs cannot fan out into repeated LLM calls. force_ai=true
  # (bypass the market-closed AI gate) additionally requires the operator token.
  # No endpoint here touches orders or positions.
  class MarketBriefsController < ApplicationController
    include Api::TokenAuthenticatable

    before_action :authenticate_dashboard_token!
    before_action :authenticate_operator_token!, only: :create, if: -> { force_ai? }

    def show
      mode = AlgoConfig.mode.to_s
      if params[:id].present?
        report = MarketBriefReport.find_by(id: params[:id].to_i)
        return render json: { success: false, error: 'not_found' }, status: :not_found unless report

        return render json: { success: true, brief: report.as_api_json, in_progress: nil }
      end

      latest = MarketBriefReport.latest_ready(mode: mode)
      in_flight = MarketBriefReport.for_mode(mode).where(status: %w[pending building]).latest_first.first
      in_flight = nil if latest && in_flight && in_flight.created_at < latest.created_at

      render json: {
        success: true,
        mode: mode,
        brief: latest&.as_api_json,
        in_progress: in_flight && { id: in_flight.id, status: in_flight.status, created_at: in_flight.created_at.iso8601 }
      }
    end

    def create
      report, created = MarketBriefReport.request!(mode: AlgoConfig.mode, trigger: 'manual')
      enqueue = created
      if report.status == 'failed'
        report.update!(status: 'pending', error: nil)
        enqueue = true
      end
      Reports::MarketBriefJob.perform_later(report.id, 'manual', force_ai?) if enqueue

      render json: { success: true, brief: report.as_api_json, enqueued: enqueue }, status: :accepted
    end

    private

    def force_ai?
      ActiveModel::Type::Boolean.new.cast(params[:force_ai]) == true
    end
  end
end
