# frozen_string_literal: true

class AlphaExecutionJob < ApplicationJob
  queue_as :default

  def perform(signal)
    result = AlphaExecutionService.execute(signal)

    if result[:status] == :success
      Rails.logger.info "[AlphaExecutionJob] Success: #{result[:order_id]} for #{signal[:alpha_source]}"
    else
      Rails.logger.warn "[AlphaExecutionJob] Failed: #{result[:reason]} for #{signal[:alpha_source]}"
      notify_failure(signal, result[:reason])
    end
  end

  private

  def notify_failure(signal, reason)
    return unless defined?(Notifications::TelegramNotifier)

    msg = "⚠️ *Alpha Execution Failed*\n" \
          "Source: #{signal[:alpha_source].to_s.titleize}\n" \
          "Index: #{signal[:index_key].to_s.upcase}\n" \
          "Reason: #{reason}"

    Notifications::TelegramNotifier.instance.send_message(msg)
  end
end
