# frozen_string_literal: true

class SwingTradingMailer < ApplicationMailer
  def recommendation_notification(recommendation)
    @recommendation = recommendation
    @watchlist_item = recommendation.watchlist_item

    subject = "[Swing Trading] #{recommendation.direction.upcase} #{recommendation.symbol_name} " \
              "- #{recommendation.recommendation_type.humanize} Recommendation"

    mail(
      to: ENV['SWING_TRADING_NOTIFICATION_EMAIL'] || 'admin@example.com',
      subject: subject
    )
  end
end
