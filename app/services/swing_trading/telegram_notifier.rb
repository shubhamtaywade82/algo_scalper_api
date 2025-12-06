# frozen_string_literal: true

require 'net/http'
require 'json'
require 'uri'

module SwingTrading
  class TelegramNotifier < ApplicationService
    TELEGRAM_API_BASE_URL = 'https://api.telegram.org/bot'.freeze

    def initialize(recommendation:)
      @recommendation = recommendation
      @bot_token = ENV['TELEGRAM_BOT_TOKEN'] || ENV['SWING_TRADING_TELEGRAM_BOT_TOKEN']
      @chat_id = ENV['TELEGRAM_CHAT_ID'] || ENV['SWING_TRADING_TELEGRAM_CHAT_ID']
    end

    def call
      return error_result('Telegram bot token not configured') unless @bot_token.present?
      return error_result('Telegram chat ID not configured') unless @chat_id.present?

      message = build_message
      send_message(message)
    rescue StandardError => e
      Rails.logger.error("[SwingTrading::TelegramNotifier] Error: #{e.class} - #{e.message}")
      Rails.logger.error("[SwingTrading::TelegramNotifier] Backtrace: #{e.backtrace.first(5).join(', ')}")
      error_result("Telegram notification failed: #{e.message}")
    end

    private

    def build_message
      rec = @recommendation
      direction_emoji = rec.direction == 'buy' ? '🟢' : '🔴'
      type_emoji = rec.recommendation_type == 'swing' ? '⚡' : '📈'

      message = <<~MESSAGE
        #{direction_emoji} *#{rec.direction.upcase} #{rec.symbol_name}* #{type_emoji}
        #{rec.recommendation_type.humanize} Recommendation

        💰 *Trade Details*
        Entry: ₹#{rec.entry_price}
        Stop Loss: ₹#{rec.stop_loss}
        Take Profit: ₹#{rec.take_profit}
        Quantity: #{rec.quantity} shares
        Investment: ₹#{rec.investment_amount}
        Allocation: #{rec.allocation_pct}%
        Hold Duration: #{rec.hold_duration_days} days
        Risk-Reward: #{rec.risk_reward_ratio}:1

        📊 *Technical Analysis*
      MESSAGE

      if rec.technical_analysis.present?
        ta = rec.technical_analysis
        message += "\n"
        message += "• Supertrend: #{ta['supertrend']&.dig('trend')&.upcase || 'N/A'}\n" if ta['supertrend']
        message += "• ADX: #{ta['adx']&.dig('value')&.round(2)} (#{ta['adx']&.dig('strength')})\n" if ta['adx']
        message += "• RSI: #{ta['rsi']&.dig('value')&.round(2)}\n" if ta['rsi']&.dig('value')
        message += "• MACD: #{ta['macd']&.dig('direction')&.upcase || 'N/A'}\n" if ta['macd']
      end

      if rec.volume_analysis.present?
        va = rec.volume_analysis
        message += "\n📈 *Volume Analysis*\n"
        message += "• Trend: #{va['trend']&.capitalize}\n"
        message += "• Volume Ratio: #{va['volume_ratio']}\n"
        volume_str = va['current_volume']&.to_s
        volume_str = volume_str.reverse.gsub(/(\d{3})(?=\d)/, '\\1,').reverse if volume_str
        message += "• Current Volume: #{volume_str}\n"
      end

      message += "\n"
      message += "🎯 *Confidence Score: #{(rec.confidence_score * 100).round(1)}%*\n" if rec.confidence_score

      if rec.reasoning.present?
        message += "\n💡 *Reasoning*\n"
        # Truncate reasoning if too long (Telegram has 4096 char limit)
        reasoning = rec.reasoning
        reasoning = reasoning[0..500] + '...' if reasoning.length > 500
        message += reasoning.split("\n").map { |line| "• #{line}" }.join("\n")
      end

      message += "\n"
      message += "⏰ Analysis Time: #{rec.analysis_timestamp.strftime('%Y-%m-%d %H:%M:%S')}\n"
      message += "⏳ Expires: #{rec.expires_at&.strftime('%Y-%m-%d %H:%M:%S')}\n" if rec.expires_at

      message
    end

    def send_message(message)
      url = URI("#{TELEGRAM_API_BASE_URL}#{@bot_token}/sendMessage")

      payload = {
        chat_id: @chat_id,
        text: message,
        parse_mode: 'Markdown',
        disable_web_page_preview: true
      }

      http = Net::HTTP.new(url.host, url.port)
      http.use_ssl = true
      http.read_timeout = 10
      http.open_timeout = 10

      request = Net::HTTP::Post.new(url.path)
      request['Content-Type'] = 'application/json'
      request.body = payload.to_json

      response = http.request(request)
      response_body = JSON.parse(response.body)

      if response.is_a?(Net::HTTPSuccess) && response_body['ok']
        Rails.logger.info("[SwingTrading::TelegramNotifier] Notification sent successfully for #{@recommendation.symbol_name}")
        success_result({ message_id: response_body['result']['message_id'] })
      else
        error_message = response_body['description'] || 'Unknown error'
        Rails.logger.error("[SwingTrading::TelegramNotifier] Failed to send notification: #{error_message}")
        error_result("Telegram API error: #{error_message}")
      end
    rescue JSON::ParserError => e
      Rails.logger.error("[SwingTrading::TelegramNotifier] JSON parse error: #{e.message}")
      error_result("Failed to parse Telegram API response")
    rescue Net::TimeoutError, Net::OpenTimeout => e
      Rails.logger.error("[SwingTrading::TelegramNotifier] Timeout error: #{e.message}")
      error_result("Telegram API timeout: #{e.message}")
    rescue StandardError => e
      Rails.logger.error("[SwingTrading::TelegramNotifier] HTTP error: #{e.class} - #{e.message}")
      error_result("HTTP error: #{e.message}")
    end

    def success_result(data)
      { success: true, data: data }
    end

    def error_result(message)
      { success: false, error: message }
    end
  end
end
