# frozen_string_literal: true

class TickerChannel < ApplicationCable::Channel
  CHANNEL_ID = :market_feed

  def subscribed
    stream_for CHANNEL_ID
    Rails.logger.info("TickerChannel subscription established (connection_id=#{connection.connection_id}).")
  end

  def unsubscribed
    stop_all_streams
  end
end
