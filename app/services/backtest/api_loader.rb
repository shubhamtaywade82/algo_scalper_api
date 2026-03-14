# frozen_string_literal: true

module Backtest
  # Loads historical intraday data using DhanHQ API
  class ApiLoader
    def initialize(symbol:, interval: '5', days: 30)
      @symbol = symbol.to_s.upcase
      @interval = interval.to_s
      @days = days
      @config = IndexTechnicalAnalyzer::INDEX_BASE_CONFIG[symbol.to_s.downcase.to_sym]
    end

    # Fetches and transforms historical data from Dhan API
    # @return [Array<Hash>] Array of tick data hashes
    def load
      return [] unless @config

      # Ensure to_date and from_date are valid trading days
      to_date = if defined?(Market::Calendar)
                  Market::Calendar.today_or_last_trading_day
                else
                  today = Date.current
                  today -= 1.day while today.saturday? || today.sunday?
                  today
                end

      from_date = if defined?(Market::Calendar)
                    Market::Calendar.trading_days_ago(@days)
                  else
                    candidate = to_date - @days.days
                    candidate -= 1.day while candidate.saturday? || candidate.sunday?
                    candidate
                  end

      Rails.logger.info("[Backtest::ApiLoader] Fetching data for #{@symbol} from #{from_date} to #{to_date} (interval: #{@interval}m)")

      response = DhanHQ::Models::HistoricalData.intraday(
        security_id: @config[:security_id],
        exchange_segment: @config[:exchange_segment],
        instrument: @config[:instrument],
        interval: @interval,
        from_date: from_date.to_s,
        to_date: to_date.to_s
      )

      # Handle response (DhanHQ gem 2.6.2 returns data hash directly on success)
      unless response.is_a?(Hash) && (response['close'] || response[:close])
        # Check for error status if present
        if response.is_a?(Hash) && (response['status'] == 'failure' || response[:status] == 'failure')
          Rails.logger.error("[Backtest::ApiLoader] API call failed for #{@symbol}: #{response.inspect}")
          return []
        end

        # If no close data and no failure status, log and return empty
        unless response.is_a?(Hash) && (response['close'] || response[:close])
          Rails.logger.error("[Backtest::ApiLoader] Unexpected API response for #{@symbol}: #{response.inspect}")
          return []
        end
      end

      # Extract data hash
      data = response

      # Handle cases where data keys are strings or symbols
      timestamps = data['timestamp'] || data[:timestamp] || []
      closes = data['close'] || data[:close] || []
      opens = data['open'] || data[:open] || []
      highs = data['high'] || data[:high] || []
      lows = data['low'] || data[:low] || []
      volumes = data['volume'] || data[:volume] || []
      ois = data['oi'] || data[:oi] || []

      return [] if timestamps.empty?

      Rails.logger.info("[Backtest::ApiLoader] Successfully loaded #{timestamps.size} candles for #{@symbol}")

      timestamps.each_with_index.map do |ts, i|
        # Normalize timestamp (can be epoch or string)
        timestamp = ts.is_a?(Numeric) ? Time.at(ts) : Time.parse(ts.to_s)

        {
          timestamp: timestamp,
          index_price: closes[i].to_f,
          open: opens[i].to_f,
          high: highs[i].to_f,
          low: lows[i].to_f,
          volume: volumes[i].to_i,
          oi: ois[i].to_i,
          option_price: closes[i].to_f * 0.01
        }
      end
    rescue StandardError => e
      Rails.logger.error("[Backtest::ApiLoader] Error loading data for #{@symbol}: #{e.class} - #{e.message}")
      []
    end
  end
end
