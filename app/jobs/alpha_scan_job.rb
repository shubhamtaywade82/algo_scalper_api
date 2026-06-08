# frozen_string_literal: true

class AlphaScanJob < ApplicationJob
  queue_as :default

  def perform(indices: %i[nifty banknifty sensex])
    return unless market_hours?

    engine = SignalEngine.new(indices: indices)
    signals = engine.run

    signals.each do |signal|
      process_signal(signal)
    end
  end

  private

  def process_signal(signal)
    Rails.logger.info "[AlphaScanJob] Signal: #{signal[:alpha_source]} | #{signal[:index_key]} #{signal[:direction].upcase} | Conf: #{signal[:confidence]}"

    # Send notification via Telegram
    notify_signal(signal)

    # Auto-execute if confidence is high
    threshold = AlgoConfig.fetch[:alpha_strategies]&.dig(:auto_execute_threshold) || 0.75
    if signal[:confidence] >= threshold
      AlphaExecutionJob.perform_later(signal)
    end
  end

  def notify_signal(signal)
    return unless defined?(Notifications::TelegramNotifier)

    msg = "🎯 *Alpha Signal Generated*\n" \
          "Source: #{signal[:alpha_source].to_s.titleize}\n" \
          "Index: #{signal[:index_key].to_s.upcase}\n" \
          "Direction: #{signal[:direction].to_s.upcase}\n" \
          "Strike: #{signal[:strike]}\n" \
          "Confidence: #{(signal[:confidence] * 100).round(1)}%\n" \
          "Expected Value: ₹#{signal[:expected_value]}"

    Notifications::TelegramNotifier.instance.send_message(msg)
  end

  def market_hours?
    now = Time.current.in_time_zone('Asia/Kolkata')
    return false if now.saturday? || now.sunday?
    now.hour >= 9 && (now.hour < 15 || (now.hour == 15 && now.min <= 30))
  end
end
