# frozen_string_literal: true

module Api
  # options-trading-agent reports what it did with an intent (intent-outcome/1). First report wins.
  class TradeIntentOutcomesController < ApplicationController
    include Api::TokenAuthenticatable

    before_action :authenticate_operator_token!

    def create
      intent = TradeIntent.find_by(intent_id: params[:trade_intent_intent_id])
      return render json: { error: 'intent_not_found' }, status: :not_found unless intent

      payload = parse_payload
      errors = payload ? Contracts::Schema.errors('intent-outcome-1', payload) : ['body is not JSON']
      errors << 'intent_id does not match the path' if payload && payload['intent_id'] != intent.intent_id
      return render json: { error: 'invalid_outcome', details: errors }, status: :unprocessable_content if errors.any?

      render json: { status: record(intent, payload) ? 'recorded' : 'already_recorded' }
    end

    private

    def parse_payload
      JSON.parse(request.raw_post)
    rescue JSON::ParserError
      nil
    end

    # Atomic compare-and-set so a retried POST can never overwrite the first outcome; the payload was
    # already validated against intent-outcome-1, which is stricter than the model validations.
    def record(intent, payload)
      TradeIntent.where(id: intent.id, outcome: nil).update_all( # rubocop:disable Rails/SkipsModelValidations
        outcome: payload['outcome'], outcome_code: payload['code'], outcome_detail: payload['detail'],
        correlation_id: payload['correlation_id'], decided_at: Time.zone.parse(payload['decided_at']),
        updated_at: Time.current
      ) == 1
    end
  end
end
