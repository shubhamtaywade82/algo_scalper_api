# frozen_string_literal: true

module Notifications
  module Telegram
    class SmcAlert
      # Cooldown period: prevent duplicate alerts for same instrument+decision
      COOLDOWN_MINUTES = 30

      # Max alerts per session per instrument
      MAX_ALERTS_PER_SESSION = 2

      def initialize(signal_event)
        @signal = signal_event
      end

      def notify!
        unless @signal.valid?
          Rails.logger.debug { "[SmcAlert] Signal invalid: decision=#{@signal.decision}, ai_analysis=#{@signal.ai_analysis.present?}" }
          return
        end

        unless telegram_enabled?
          Rails.logger.debug('[SmcAlert] Telegram not enabled')
          return
        end

        if duplicate_alert?
          Rails.logger.debug('[SmcAlert] Duplicate alert suppressed')
          return
        end

        if cooldown_active?
          Rails.logger.debug('[SmcAlert] Cooldown active')
          return
        end

        if max_alerts_reached?
          Rails.logger.debug('[SmcAlert] Max alerts reached')
          return
        end

        message = format_message

        Rails.logger.info("[SmcAlert] Sending alert for #{@signal.instrument.symbol_name} - #{@signal.decision} (#{message.length} chars)")

        # Client will automatically split into chunks if needed
        success = client.send_message(message)
        unless success
          Rails.logger.warn('[SmcAlert] Failed to send message')
          return
        end

        # Client.send_message returns true if all chunks sent successfully
        record_alert_sent
        Rails.logger.info("[SmcAlert] Alert sent successfully for #{@signal.instrument.symbol_name} - #{@signal.decision}")
      end

      private

      def telegram_enabled?
        AlgoConfig.fetch.dig(:telegram, :enabled) == true &&
          ENV['TELEGRAM_BOT_TOKEN'].present? &&
          ENV['TELEGRAM_CHAT_ID'].present?
      rescue StandardError
        false
      end

      def client
        @client ||= Client.new(
          token: ENV.fetch('TELEGRAM_BOT_TOKEN'),
          chat_id: ENV.fetch('TELEGRAM_CHAT_ID')
        )
      end

      def cooldown_minutes
        AlgoConfig.fetch.dig(:telegram, :smc_alert_cooldown_minutes) || COOLDOWN_MINUTES
      rescue StandardError
        COOLDOWN_MINUTES
      end

      def max_alerts_per_session
        AlgoConfig.fetch.dig(:telegram, :smc_max_alerts_per_session) || MAX_ALERTS_PER_SESSION
      rescue StandardError
        MAX_ALERTS_PER_SESSION
      end

      def format_message
        strikes_info = format_strikes
        strikes_section = strikes_info ? "\n\n#{strikes_info}" : ''
        ai_section = format_ai_analysis

        signal_type = @signal.decision == :no_trade ? 'ANALYSIS' : 'SIGNAL'
        instrument_name = escape_html(@signal.instrument.symbol_name)
        decision_text = escape_html(@signal.decision.to_s.upcase)
        timeframe_text = escape_html(@signal.timeframe)
        price_text = escape_html(@signal.price.to_s)
        time_text = escape_html(Time.current.strftime('%d %b %Y, %H:%M'))

        <<~MSG
          🚨 <b>SMC + AVRZ #{escape_html(signal_type)}</b>

          📌 <b>Instrument</b>: #{instrument_name}
          📊 <b>Action</b>: #{decision_text}
          ⏱ <b>Timeframe</b>: #{timeframe_text}
          💰 <b>Spot Price</b>: #{price_text}

          🧠 <b>Confluence</b>:
          #{formatted_reasons}#{strikes_section}#{ai_section}

          🕒 <b>Time</b>: #{time_text}
        MSG
      end

      def format_ai_analysis
        return '' unless @signal.ai_analysis.present?

        # Truncate AI analysis if too long (Telegram has 4096 char limit)
        analysis = @signal.ai_analysis.to_s.strip

        # Escape HTML special characters
        analysis = escape_html(analysis)

        # Truncate if still too long (leave room for header)
        analysis = "#{analysis[0..1997]}..." if analysis.length > 2000

        "\n\n🤖 <b>AI Analysis</b>:\n#{analysis}"
      end

      def format_strikes
        strikes_data = fetch_atm_strikes_with_premiums
        return nil unless strikes_data && strikes_data[:atm_strike]

        atm = strikes_data[:atm_strike]
        interval = strikes_data[:strike_interval]
        lot_size = strikes_data[:lot_size] || 50
        call_options = strikes_data[:call_options] || []
        put_options = strikes_data[:put_options] || []

        lines = []
        lines << "📊 <b>Option Strikes</b> (Lot: #{escape_html(lot_size.to_s)}):"
        lines << "ATM: #{escape_html(atm.to_s)}"

        if call_options.any?
          call_parts = call_options.map do |opt|
            if opt[:strike] == atm
              label = "#{escape_html(opt[:strike].to_s)} (ATM)"
            else
              offset = (opt[:strike] - atm) / interval
              label = "#{escape_html(opt[:strike].to_s)} (ATM+#{escape_html(offset.to_s)})"
            end
            premium = opt[:premium] ? "₹#{escape_html(opt[:premium].round(2).to_s)}" : 'N/A'
            "#{label} @ #{premium}"
          end
          lines << "CALL: #{call_parts.join(', ')}"
        end

        if put_options.any?
          put_parts = put_options.map do |opt|
            if opt[:strike] == atm
              label = "#{escape_html(opt[:strike].to_s)} (ATM)"
            else
              offset = (opt[:strike] - atm) / interval
              label = "#{escape_html(opt[:strike].to_s)} (ATM-#{escape_html(offset.to_s)})"
            end
            premium = opt[:premium] ? "₹#{escape_html(opt[:premium].round(2).to_s)}" : 'N/A'
            "#{label} @ #{premium}"
          end
          lines << "PUT: #{put_parts.join(', ')}"
        end

        # Add quantity suggestion (1 lot)
        if call_options.any? || put_options.any?
          lines << "💡 <b>Suggested Qty</b>: #{escape_html(lot_size.to_s)} (1 lot)"
        end

        lines.join("\n")
      rescue StandardError => e
        Rails.logger.debug { "[SmcAlert] Failed to format strikes: #{e.class} - #{e.message}" }
        nil
      end

      def fetch_atm_strikes_with_premiums
        return nil unless @signal.instrument.respond_to?(:fetch_option_chain)

        # Fetch option chain
        chain_data = @signal.instrument.fetch_option_chain
        return nil unless chain_data && chain_data[:oc]&.any?

        spot_price = chain_data[:last_price]&.to_f || @signal.price.to_f
        return nil unless spot_price.positive?

        # Get available strikes (keys are strings like "24000.000000")
        strike_map = {} # float => string key mapping
        chain_data[:oc].each do |strike_str, _data|
          strike_float = strike_str.to_f
          strike_map[strike_float] = strike_str
        end

        available_strikes = strike_map.keys.sort
        return nil unless available_strikes.any?

        # Calculate strike interval
        strike_interval = available_strikes.size >= 2 ? (available_strikes[1] - available_strikes[0]) : 50

        # Find ATM strike (closest to spot)
        atm_strike = available_strikes.min_by { |s| (s - spot_price).abs }

        # Get lot size from index config
        lot_size = get_lot_size_for_instrument

        # Get ATM and ATM+1 for CALL (CE) with premiums
        call_options = [
          atm_strike,
          atm_strike + strike_interval
        ].filter_map do |strike_float|
          strike_str = strike_map[strike_float]
          ce_data = chain_data[:oc][strike_str]&.dig('ce')
          next unless strike_str && ce_data.is_a?(Hash)

          option_data = ce_data
          premium = option_data['last_price']&.to_f

          {
            strike: strike_float,
            premium: premium,
            iv: option_data['implied_volatility']&.to_f,
            oi: option_data['oi']&.to_i
          }
        end

        # Get ATM and ATM-1 for PUT (PE) with premiums
        put_options = [
          atm_strike,
          atm_strike - strike_interval
        ].filter_map do |strike_float|
          strike_str = strike_map[strike_float]
          pe_data = chain_data[:oc][strike_str]&.dig('pe')
          next unless strike_str && pe_data.is_a?(Hash)

          option_data = pe_data
          premium = option_data['last_price']&.to_f

          {
            strike: strike_float,
            premium: premium,
            iv: option_data['implied_volatility']&.to_f,
            oi: option_data['oi']&.to_i
          }
        end

        {
          atm_strike: atm_strike,
          strike_interval: strike_interval,
          call_options: call_options,
          put_options: put_options,
          spot_price: spot_price,
          lot_size: lot_size
        }
      rescue StandardError => e
        Rails.logger.debug { "[SmcAlert] Failed to fetch ATM strikes: #{e.class} - #{e.message}" }
        nil
      end

      def get_lot_size_for_instrument
        # Try to get from index config
        symbol_name = @signal.instrument.symbol_name.to_s.upcase
        index_cfg = IndexConfigLoader.load_indices.find { |idx| idx[:key].to_s.upcase == symbol_name }
        return index_cfg[:lot_size].to_i if index_cfg && index_cfg[:lot_size]

        # Fallback to index rules
        case symbol_name
        when 'NIFTY'
          Options::IndexRules::Nifty.new.lot_size
        when 'BANKNIFTY'
          Options::IndexRules::Banknifty.new.lot_size
        when 'SENSEX'
          Options::IndexRules::Sensex.new.lot_size
        else
          50 # Default fallback
        end
      rescue StandardError => e
        Rails.logger.debug { "[SmcAlert] Failed to get lot size: #{e.class} - #{e.message}" }
        50 # Default fallback
      end

      def formatted_reasons
        @signal.reasons.map { |r| "• #{escape_html(r)}" }.join("\n")
      end

      def escape_html(text)
        # Escape HTML special characters for Telegram HTML parse mode
        text.to_s.gsub('&', '&amp;').gsub('<', '&lt;').gsub('>', '&gt;')
      end

      def cache_key
        "smc:alert:#{@signal.instrument.symbol_name}:#{@signal.decision}"
      end

      def session_key
        "smc:session:#{@signal.instrument.symbol_name}:#{trading_date}"
      end

      def trading_date
        Time.zone.today.to_s
      end

      def duplicate_alert?
        last_alert = Rails.cache.read(cache_key)
        return false unless last_alert

        # Check if this is the same price level (within 0.1% to avoid noise)
        last_price = last_alert[:price].to_f
        current_price = @signal.price.to_f
        price_diff_pct = ((current_price - last_price).abs / last_price * 100).round(2)

        if price_diff_pct < 0.1
          Rails.logger.debug { "[SmcAlert] Duplicate alert suppressed: #{@signal.instrument.symbol_name} #{@signal.decision} at similar price (#{price_diff_pct}% diff)" }
          true
        else
          false
        end
      end

      def cooldown_active?
        last_alert = Rails.cache.read(cache_key)
        return false unless last_alert

        last_sent_at = last_alert[:sent_at]
        return false unless last_sent_at

        cooldown_seconds = cooldown_minutes * 60
        time_since_last = Time.current.to_i - last_sent_at.to_i

        if time_since_last < cooldown_seconds
          remaining_minutes = ((cooldown_seconds - time_since_last) / 60.0).ceil
          Rails.logger.debug { "[SmcAlert] Cooldown active: #{@signal.instrument.symbol_name} #{@signal.decision} (#{remaining_minutes}m remaining)" }
          true
        else
          false
        end
      end

      def max_alerts_reached?
        session_alerts = Rails.cache.read(session_key) || []
        count = session_alerts.count { |a| a[:decision] == @signal.decision }

        max_allowed = max_alerts_per_session
        if count >= max_allowed
          Rails.logger.debug { "[SmcAlert] Max alerts reached for #{@signal.instrument.symbol_name} #{@signal.decision} (#{count}/#{max_allowed})" }
          true
        else
          false
        end
      end

      def record_alert_sent
        # Record last alert (with cooldown TTL)
        Rails.cache.write(
          cache_key,
          {
            sent_at: Time.current.to_i,
            price: @signal.price,
            decision: @signal.decision
          },
          expires_in: cooldown_minutes.minutes
        )

        # Record session alert count
        session_alerts = Rails.cache.read(session_key) || []
        session_alerts << {
          decision: @signal.decision,
          price: @signal.price,
          sent_at: Time.current.to_i
        }
        # Keep only last 10 alerts for this session
        session_alerts = session_alerts.last(10)

        # Session cache expires at end of trading day (next day 00:00)
        expires_at = Time.zone.tomorrow.beginning_of_day
        Rails.cache.write(session_key, session_alerts, expires_at: expires_at)
      end
    end
  end
end
