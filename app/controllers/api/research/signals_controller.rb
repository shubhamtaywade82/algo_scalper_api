# frozen_string_literal: true

module Api
  module Research
    # Read/create surface for Research::Signal + its scored option candidates —
    # powers the dashboard's Research page "Signal Pipeline" panel. Creating a
    # signal here synchronously runs Research::Pipeline (real DhanHQ calls,
    # same as lib/tasks/research.rake) — this is an offline research tool, not
    # part of the live trading path.
    class SignalsController < ApplicationController
      include Api::TokenAuthenticatable
      include Api::Research::Paginatable

      before_action :authenticate_dashboard_token!

      def index
        scope = ::Research::Signal.order(signal_timestamp: :desc)
        scope = scope.where(underlying_symbol: params[:underlying_symbol].to_s.upcase) if params[:underlying_symbol].present?
        scope = scope.where(direction: params[:direction]) if params[:direction].present?

        records, meta = paginate(scope)
        render json: { signals: records.map { |signal| serialize_signal(signal) }, meta: meta }
      end

      def show
        signal = ::Research::Signal.find(params.expect(:id))
        candidates = signal.option_candidates.order(:option_type, :strike_distance)
        render json: { signal: serialize_signal(signal), candidates: candidates.map { |c| serialize_candidate(c) } }
      rescue ActiveRecord::RecordNotFound
        render json: { error: "not_found" }, status: :not_found
      end

      def create
        signal = ::Research::SignalSnapshotBuilder.build(
          underlying_symbol: params.require(:underlying_symbol),
          signal_timestamp: parse_time!(params.require(:signal_timestamp)),
          direction: params.require(:direction),
          spot_price: params.require(:spot_price),
          strategy_name: params[:strategy_name].presence || "dashboard_manual"
        )

        candidates = ::Research::Pipeline.run(
          signal: signal,
          expiry_flags: [params[:expiry_flag].presence || "WEEK"],
          max_distance: (params[:max_distance] || 2).to_i.clamp(0, 10),
          entry_model: params[:entry_model].presence || "next_candle_open"
        )

        render json: { signal: serialize_signal(signal), candidates: candidates.map { |c| serialize_candidate(c) } },
               status: :created
      rescue ActionController::ParameterMissing, ArgumentError, ActiveRecord::RecordInvalid => e
        render json: { error: e.message }, status: :unprocessable_content
      end

      private

      def parse_time!(value)
        Time.zone.parse(value.to_s) || raise(ArgumentError, "invalid signal_timestamp: #{value}")
      end

      def serialize_signal(signal)
        {
          id: signal.id,
          strategy_name: signal.strategy_name,
          underlying_symbol: signal.underlying_symbol,
          signal_timestamp: signal.signal_timestamp&.iso8601,
          direction: signal.direction,
          spot_price: signal.spot_price&.to_f,
          confidence: signal.confidence&.to_f,
          source: signal.source,
          candidate_count: signal.option_candidates.size,
          created_at: signal.created_at&.iso8601
        }
      end

      def serialize_candidate(candidate)
        {
          id: candidate.id,
          expiry_flag: candidate.expiry_flag,
          option_type: candidate.option_type,
          strike_label: candidate.strike_label,
          strike_distance: candidate.strike_distance,
          actual_strike: candidate.actual_strike&.to_f,
          entry_model: candidate.entry_model,
          status: candidate.status,
          entry_timestamp: candidate.entry_timestamp&.iso8601,
          entry_price: candidate.entry_price&.to_f,
          exit_timestamp: candidate.exit_timestamp&.iso8601,
          exit_price: candidate.exit_price&.to_f,
          mfe_pct: candidate.mfe_pct&.to_f,
          mae_pct: candidate.mae_pct&.to_f,
          return_pct: candidate.return_pct&.to_f,
          holding_minutes: candidate.holding_minutes
        }
      end
    end
  end
end
