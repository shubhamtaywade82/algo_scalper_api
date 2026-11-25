# frozen_string_literal: true

module Api
  # Pull endpoint for options-trading-agent (trade-intents/1 envelope). The agent polls; Rails never pushes.
  class TradeIntentsController < ApplicationController
    include Api::TokenAuthenticatable

    before_action :authenticate_operator_token!

    MAX_BATCH = 50

    def index
      after = params[:after].to_i
      intents = TradeIntent.pending.where(mode: params.fetch(:mode, 'paper'))
                           .where('id > ?', after).order(:id).limit(MAX_BATCH).to_a

      render json: {
        schema: 'trade-intents/1',
        cursor: (intents.last&.id || after).to_s,
        intents: intents.map(&:payload),
        control: control_block
      }
    end

    private

    def control_block
      {
        circuit_breaker: { tripped: Risk::CircuitBreaker.instance.tripped? },
        intake_enabled: TradeIntents::Forwarder.agent_engine?,
        server_time: Time.current.iso8601(3)
      }
    end
  end
end
