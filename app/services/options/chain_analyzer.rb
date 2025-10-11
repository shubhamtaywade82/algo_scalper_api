# frozen_string_literal: true

module Options
  class ChainAnalyzer
    class << self
      def pick_strikes(index_cfg:, direction:)
        Rails.logger.info("[Options] Starting strike selection for #{index_cfg[:key]} #{direction}")

        # Get cached index instrument
        instrument = IndexInstrumentCache.instance.get_or_fetch(index_cfg)
        unless instrument
          Rails.logger.warn("[Options] No instrument found for #{index_cfg[:key]}")
          return []
        end
        Rails.logger.debug("[Options] Using instrument: #{instrument.symbol_name}")

        # Use instrument's existing methods to get expiry list and option chain
        expiry_list = instrument.expiry_list
        unless expiry_list&.any?
          Rails.logger.warn("[Options] No expiry list available for #{index_cfg[:key]}")
          return []
        end
        Rails.logger.debug("[Options] Available expiries: #{expiry_list}")

        # Get the next upcoming expiry
        expiry_date = find_next_expiry(expiry_list)
        unless expiry_date
          Rails.logger.warn("[Options] Could not determine next expiry for #{index_cfg[:key]}")
          return []
        end
        Rails.logger.info("[Options] Using expiry: #{expiry_date}")

        # Fetch option chain using instrument's method
        chain_data = instrument.fetch_option_chain(expiry_date)
        unless chain_data
          Rails.logger.warn("[Options] No option chain data for #{index_cfg[:key]} #{expiry_date}")
          return []
        end

        Rails.logger.debug("[Options] Chain data structure: #{chain_data.keys}")
        Rails.logger.debug("[Options] OC data size: #{chain_data[:oc]&.size || 'nil'}")

        # Debug: Show sample of raw option data
        if chain_data[:oc] && chain_data[:oc].any?
          sample_strike = chain_data[:oc].keys.first
          sample_data = chain_data[:oc][sample_strike]
          Rails.logger.debug("[Options] Sample strike #{sample_strike} data: #{sample_data}")
          if sample_data["pe"]
            Rails.logger.debug("[Options] Sample PE data: #{sample_data["pe"]}")
          end
        end

        atm_price = chain_data[:last_price]
        unless atm_price
          Rails.logger.warn("[Options] No ATM price available for #{index_cfg[:key]}")
          return []
        end
        Rails.logger.info("[Options] ATM price: #{atm_price}")

        side = direction == :bullish ? :ce : :pe
        window = atm_price.to_f * (AlgoConfig.fetch.dig(:option_chain, :atm_window_pct).to_f / 100.0)
        Rails.logger.debug("[Options] Looking for #{side} options within #{window} points of ATM")

        legs = filter_and_rank_from_instrument_data(chain_data[:oc], atm: atm_price, side: side, window: window, index_cfg: index_cfg, expiry_date: expiry_date, instrument: instrument)
        Rails.logger.info("[Options] Found #{legs.size} qualifying #{side} options for #{index_cfg[:key]}")

        if legs.any?
          Rails.logger.info("[Options] Top picks: #{legs.first(2).map { |l| "#{l[:symbol]}@#{l[:strike]} (IV:#{l[:iv]}, OI:#{l[:oi]})" }.join(', ')}")
        end

        legs.first(2).map do |leg|
          leg.slice(:segment, :security_id, :symbol, :ltp, :iv, :oi, :spread, :lot_size)
        end
      end

      def find_next_expiry(expiry_list)
        return nil unless expiry_list&.any?

        today = Date.current
        upcoming_expiries = expiry_list
          .map { |date_str| Date.parse(date_str.to_s) rescue nil }
          .compact
          .select { |date| date > today }
          .sort

        upcoming_expiries.first&.strftime("%Y-%m-%d")
      rescue StandardError => e
        Rails.logger.warn("Failed to parse expiry list: #{e.class} - #{e.message}")
        calculate_next_trading_day
      end

      def calculate_next_trading_day
        # Use Market::Calendar to find the next trading day dynamically
        # This replaces the hardcoded Thursday logic
        Market::Calendar.next_trading_day.strftime("%Y-%m-%d")
      end

      def filter_and_rank_from_instrument_data(option_chain_data, atm:, side:, window:, index_cfg:, expiry_date:, instrument:)
        # Force reload - debugging index_cfg scope issue
        return [] unless option_chain_data

        Rails.logger.debug("[Options] Method called with index_cfg: #{index_cfg[:key]}, expiry_date: #{expiry_date}")

        Rails.logger.debug("[Options] Processing #{option_chain_data.size} strikes for #{side} options")
        Rails.logger.debug("[Options] ATM: #{atm}, Window: #{window} (#{atm - window} to #{atm + window})")

        min_iv = AlgoConfig.fetch.dig(:option_chain, :min_iv).to_f
        max_iv = AlgoConfig.fetch.dig(:option_chain, :max_iv).to_f
        min_oi = AlgoConfig.fetch.dig(:option_chain, :min_oi).to_i
        max_spread_pct = AlgoConfig.fetch.dig(:option_chain, :max_spread_pct).to_f

        Rails.logger.debug("[Options] Filter criteria: IV(#{min_iv}-#{max_iv}), OI(>=#{min_oi}), Spread(<=#{max_spread_pct}%)")

        legs = []
        rejected_count = 0

        option_chain_data.each do |strike_str, strike_data|
          strike = strike_str.to_f

          # Check ATM window first
          unless (atm - window) <= strike && strike <= (atm + window)
            rejected_count += 1
            next
          end

          option_data = strike_data[side.to_s]
          unless option_data
            rejected_count += 1
            next
          end

          # Debug: Show available fields for first few strikes
          if rejected_count < 3
            Rails.logger.debug("[Options] Available fields for #{side}: #{option_data.keys}")
          end

          ltp = option_data["last_price"]&.to_f
          iv = option_data["implied_volatility"]&.to_f
          oi = option_data["oi"]&.to_i
          bid = option_data["top_bid_price"]&.to_f
          ask = option_data["top_ask_price"]&.to_f

          Rails.logger.debug("[Options] Strike #{strike}: LTP=#{ltp}, IV=#{iv}, OI=#{oi}, Bid=#{bid}, Ask=#{ask}")

          # Check LTP
          unless ltp && ltp > 0
            rejected_count += 1
            Rails.logger.debug("[Options] Rejected #{strike}: Invalid LTP")
            next
          end

          # Check IV
          unless iv && iv >= min_iv && iv <= max_iv
            rejected_count += 1
            Rails.logger.debug("[Options] Rejected #{strike}: IV #{iv} not in range #{min_iv}-#{max_iv}")
            next
          end

          # Check OI
          unless oi && oi >= min_oi
            rejected_count += 1
            Rails.logger.debug("[Options] Rejected #{strike}: OI #{oi} < #{min_oi}")
            next
          end

          # Calculate spread percentage
          if bid && ask && bid > 0
            spread_pct = ((ask - bid) / bid) * 100
            if spread_pct > max_spread_pct
              rejected_count += 1
              Rails.logger.debug("[Options] Rejected #{strike}: Spread #{spread_pct}% > #{max_spread_pct}%")
              next
            end
          end

          # Find the derivative security ID using instrument.derivatives association
          # Filter by strike, expiry date, and option type
          expiry_date_obj = Date.parse(expiry_date)
          option_type = side.to_s.upcase # CE or PE

          derivative = instrument.derivatives.find do |d|
            d.strike_price == strike.to_f &&
            d.expiry_date == expiry_date_obj &&
            d.option_type == option_type
          end

          if derivative
            Rails.logger.debug("[Options] Found derivative for #{index_cfg[:key]} #{strike} #{side}: security_id=#{derivative.security_id}, lot_size=#{derivative.lot_size}")
            security_id = derivative.security_id
          else
            Rails.logger.warn("[Options] No derivative found for #{index_cfg[:key]} #{strike} #{side} #{expiry_date}")
            security_id = nil
          end

          legs << {
            segment: "NSE_FNO", # Default segment for index options
            security_id: security_id,
            symbol: "#{index_cfg[:key]}-#{expiry_date_obj.strftime('%b%Y')}-#{strike.to_i}-#{side.to_s.upcase}",
            strike: strike,
            ltp: ltp,
            iv: iv,
            oi: oi,
            spread: ask && bid ? (ask - bid) : nil,
            distance_from_atm: (strike - atm).abs,
            lot_size: derivative&.lot_size || index_cfg[:lot].to_i
          }

          Rails.logger.debug("[Options] Accepted #{strike}: #{legs.last[:symbol]}")
        end

        Rails.logger.info("[Options] Filter results: #{legs.size} accepted, #{rejected_count} rejected")

        # Sort by distance from ATM, then by OI (descending)
        legs.sort_by { |leg| [ leg[:distance_from_atm], -leg[:oi] ] }
      end

      def filter_and_rank(legs, atm:, side:, window:)
        return [] unless legs

        min_iv = AlgoConfig.fetch.dig(:option_chain, :min_iv).to_f
        max_iv = AlgoConfig.fetch.dig(:option_chain, :max_iv).to_f
        min_oi = AlgoConfig.fetch.dig(:option_chain, :min_oi).to_i
        max_spread_pct = AlgoConfig.fetch.dig(:option_chain, :max_spread_pct).to_f

        legs.select do |leg|
          leg[:type] == side &&
            (leg[:strike].to_f - atm.to_f).abs <= window &&
            leg[:iv].to_f.between?(min_iv, max_iv) &&
            leg[:oi].to_i >= min_oi &&
            leg.fetch(:spread_pct, 0.0).to_f <= max_spread_pct
        end.sort_by { |leg| [ -leg[:oi].to_i, leg.fetch(:spread_pct, 0.0).to_f ] }
      end
    end
  end
end
