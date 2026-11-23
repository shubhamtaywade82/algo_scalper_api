# frozen_string_literal: true

module Options
  class ChainAnalyzer
    module LegRanker
      def filter_and_rank(legs, atm:, side:, window:)
        return [] unless legs

        min_iv = AlgoConfig.fetch.dig(:option_chain, :min_iv).to_f
        max_iv = AlgoConfig.fetch.dig(:option_chain, :max_iv).to_f
        min_oi = AlgoConfig.fetch.dig(:option_chain, :min_oi).to_i
        max_spread_pct = AlgoConfig.fetch.dig(:option_chain, :max_spread_pct).to_f

        # rubocop:disable-next Style/MultilineBlockChain
        legs.select do |leg|
          leg[:type] == side &&
            (leg[:strike].to_f - atm.to_f).abs <= window &&
            leg[:iv].to_f.between?(min_iv, max_iv) &&
            leg[:oi].to_i >= min_oi &&
            leg.fetch(:spread_pct, 0.0).to_f <= max_spread_pct
        end.sort_by { |leg| [-leg[:oi].to_i, leg.fetch(:spread_pct, 0.0).to_f] }
      end

      # rubocop:disable-next Metrics/ParameterLists
      def filter_and_rank_from_instrument_data(option_chain_data, atm:, side:, index_cfg:, expiry_date:, instrument:,
                                               target_strikes: nil, flow_results: nil, gamma_pressure: 0.0,
                                               prop_selector: nil, flow_analyzer: nil, index_prices: nil)
        return [] unless option_chain_data

        flow_side = side.to_s.downcase
        flow_scores = extract_flow_scores(flow_results, flow_side)
        strikes = option_chain_data.keys.map(&:to_f).sort
        strike_interval = self.strike_interval(strikes)
        atm_strike = (atm / strike_interval).round * strike_interval
        atm_range_percent = atm_range_pct(0.5)

        targets = resolve_target_strikes(target_strikes, side, atm_strike, strike_interval, option_chain_data)
        log_strike_selection_guidance(side, atm, atm_strike, targets, 0.5, atm_range_percent, strike_interval)

        legs, rejected_count = collect_qualifying_legs(
          option_chain_data, targets: targets, atm_strike: atm_strike, strike_interval: strike_interval,
                             side: side, expiry_date: expiry_date, instrument: instrument, index_cfg: index_cfg
        )

        cfg = AlgoConfig.fetch[:option_chain] || {}
        log_filtering_summary(side, legs.size, rejected_count, cfg[:min_iv], cfg[:max_iv], cfg[:min_oi], cfg[:max_spread_pct], min_delta_now)

        score_and_sort_legs(legs, side: side, atm_strike: atm_strike, atm_range_percent: atm_range_percent,
                                  flow_scores: flow_scores, flow_analyzer: flow_analyzer, flow_side: flow_side,
                                  gamma_pressure: gamma_pressure, prop_selector: prop_selector, index_prices: index_prices)
      end

      def valid_security_id?(value)
        id = value.to_s
        return false if id.blank?
        return false if id.start_with?('TEST_')

        true
      end

      def derivative_like?(row)
        row.respond_to?(:expiry_date) && row.respond_to?(:option_type) && row.respond_to?(:strike_price)
      end

      def resolve_derivative_segment(derivative, underlying)
        synced = if derivative.respond_to?(:exchange_segment) then derivative.exchange_segment
                 elsif derivative.is_a?(Hash) then derivative[:exchange_segment]
                 end
        return synced if synced.present?

        derived = "#{underlying.try(:exchange).to_s.upcase}_FNO"
        %w[NSE_FNO BSE_FNO].include?(derived) ? derived : nil
      end

      def use_option_chain_security_id?
        cfg = AlgoConfig.fetch
        return true unless cfg.is_a?(Hash)

        value = cfg.dig(:chain_analyzer, :use_option_chain_security_id)
        return true if value.nil?

        value == true
      rescue StandardError
        true
      end

      def log_strike_selection_guidance(side, spot, atm_strike, target_strikes, iv_rank, _atm_range_percent,
                                        strike_interval)
        _iv_rank_label = case iv_rank
                         when 0.0..0.2 then 'Low'
                         when 0.2..0.5 then 'Medium'
                         else 'High'
                         end
        _strike_guidance = side.to_s == 'ce' ? 'CE strikes: ATM, ATM+1, ATM+2, ATM+3' : 'PE strikes: ATM, ATM-1, ATM-2, ATM-3'
        target_strikes.each do |strike|
          _diff = (strike - atm_strike).abs
          _dist_spot = (strike - spot).abs
          _step = strike_interval
        end
      end

      def log_filtering_summary(_side, accepted_count, rejected_count, _min_iv, _max_iv, _min_oi, _max_spread_pct, _min_delta)
        total = accepted_count + rejected_count
        _pct = total.positive? ? (accepted_count.to_f / total * 100).round(1) : 0
      end

      private

      def extract_flow_scores(flow_results, flow_side)
        (flow_results&.[](flow_side) || []).to_h { |f| [f[:strike].to_f, f[:score]] }
      end

      def resolve_target_strikes(target_strikes, side, atm_strike, strike_interval, option_chain_data)
        computed = if side.to_s == 'ce'
                     [atm_strike, atm_strike + strike_interval, atm_strike + (2 * strike_interval)]
                   else
                     [atm_strike, atm_strike - strike_interval, atm_strike - (2 * strike_interval)]
                   end
        available = option_chain_data.keys.map(&:to_f)
        (target_strikes.presence || computed).map(&:to_f).select { |s| available.include?(s) }
      end

      # rubocop:disable-next Metrics/ParameterLists
      def collect_qualifying_legs(option_chain_data, targets:, atm_strike:, strike_interval:, side:, expiry_date:, instrument:, index_cfg:)
        legs = []
        rejected_count = 0
        min_iv = AlgoConfig.fetch.dig(:option_chain, :min_iv).to_f
        max_iv = AlgoConfig.fetch.dig(:option_chain, :max_iv).to_f
        min_oi = AlgoConfig.fetch.dig(:option_chain, :min_oi).to_i
        max_spread_pct = AlgoConfig.fetch.dig(:option_chain, :max_spread_pct).to_f
        min_delta = min_delta_now
        use_oc_sec_id = use_option_chain_security_id?

        option_chain_data.each do |strike_str, strike_data|
          strike = strike_str.to_f
          unless targets.include?(strike) && strike_data[side.to_s]
            rejected_count += 1
            next
          end

          opt_data = strike_data[side.to_s]
          unless option_passes_filters?(opt_data, strike: strike, atm_strike: atm_strike, strike_interval: strike_interval,
                                                  min_iv: min_iv, max_iv: max_iv, min_oi: min_oi,
                                                  max_spread_pct: max_spread_pct, min_delta: min_delta)
            rejected_count += 1
            next
          end

          leg = build_qualifying_leg(opt_data, strike: strike, side: side, expiry_date: expiry_date,
                                               instrument: instrument, index_cfg: index_cfg, use_oc_sec_id: use_oc_sec_id)
          if leg
            legs << leg
          else
            rejected_count += 1
          end
        end

        [legs, rejected_count]
      end

      # rubocop:disable-next Metrics/ParameterLists
      def option_passes_filters?(opt_data, strike:, atm_strike:, strike_interval:, min_iv:, max_iv:, min_oi:, max_spread_pct:, min_delta:)
        ltp = opt_data['last_price']&.to_f
        iv = opt_data['implied_volatility']&.to_f
        oi = opt_data['oi']&.to_i
        bid = opt_data['top_bid_price']&.to_f
        ask = opt_data['top_ask_price']&.to_f
        delta = opt_data.dig('greeks', 'delta')&.to_f&.abs

        return false unless ltp&.positive? && oi && oi >= min_oi

        iv_thresh = if strike == atm_strike then [5.0, min_iv * 0.6].max
                    elsif (strike - atm_strike).abs <= strike_interval then [7.0, min_iv * 0.8].max
                    else min_iv
                    end
        return false unless iv && iv >= iv_thresh && iv <= max_iv

        if bid && ask && bid.positive?
          spread_pct = ((ask - bid) / bid) * 100
          return false if spread_pct > max_spread_pct
        end

        return false unless delta && delta >= min_delta

        true
      end

      # rubocop:disable-next Metrics/ParameterLists
      def build_qualifying_leg(opt_data, strike:, side:, expiry_date:, instrument:, index_cfg:, use_oc_sec_id:)
        expiry_date_obj = Date.parse(expiry_date)
        option_type = side.to_s.upcase
        strike_bd = BigDecimal(strike.to_s)

        derivative = find_matching_derivative(instrument, strike_bd: strike_bd, expiry_date_obj: expiry_date_obj,
                                                          option_type: option_type, index_cfg: index_cfg)

        security_id = resolve_leg_security_id(opt_data['security_id'], derivative, use_oc_sec_id: use_oc_sec_id)
        return nil unless valid_security_id?(security_id)
        return nil if !use_oc_sec_id && derivative.nil?
        return nil if derivative && derivative_mismatch?(derivative, strike_bd: strike_bd,
                                                                     expiry_date_obj: expiry_date_obj, option_type: option_type)

        segment = resolve_derivative_segment(derivative, instrument)
        return nil unless segment

        lot = derivative&.lot_size.to_i
        lot_size = lot.positive? ? lot : Trading::LotCalculator.lot_size_for(index_cfg[:key])
        bid = opt_data['top_bid_price']&.to_f
        ask = opt_data['top_ask_price']&.to_f
        spread_ratio = bid && ask && bid.positive? ? ((ask - bid) / bid) : nil

        {
          segment: segment,
          security_id: security_id,
          symbol: "#{index_cfg[:key]}-#{expiry_date_obj.strftime('%b%Y')}-#{strike.to_i}-#{side.to_s.upcase}",
          strike: strike,
          ltp: opt_data['last_price']&.to_f,
          iv: opt_data['implied_volatility']&.to_f,
          oi: opt_data['oi']&.to_i,
          spread: spread_ratio,
          delta: opt_data.dig('greeks', 'delta')&.to_f&.abs,
          distance_from_atm: (strike - strike_bd.to_f).abs,
          lot_size: lot_size,
          instrument_id: derivative&.id,
          derivative_id: derivative&.id
        }
      end

      def find_matching_derivative(instrument, strike_bd:, expiry_date_obj:, option_type:, index_cfg:)
        coll = instrument.respond_to?(:derivative_contracts) ? instrument.derivative_contracts : nil
        derivative = if coll.respond_to?(:where)
                       coll.where(expiry_date: expiry_date_obj, option_type: option_type).detect do |d|
                         BigDecimal(d.strike_price.to_s) == strike_bd
                       end
                     elsif coll.present?
                       Array(coll).detect do |d|
                         derivative_like?(d) && d.expiry_date == expiry_date_obj &&
                           d.option_type.to_s.upcase == option_type && BigDecimal(d.strike_price.to_s) == strike_bd
                       end
                     end

        derivative ||= Instrument.where(underlying_instrument_id: instrument.id, expiry_date: expiry_date_obj, option_type: option_type).detect { |d| BigDecimal(d.strike_price.to_s) == strike_bd }
        derivative ||= Instrument.where(underlying_symbol: instrument.symbol_name, exchange: instrument.exchange, expiry_date: expiry_date_obj, option_type: option_type).detect { |d| BigDecimal(d.strike_price.to_s) == strike_bd }
        derivative || Instrument.find_derivative_by_params(underlying_symbol: index_cfg[:key], strike_price: strike_bd.to_f, expiry_date: expiry_date_obj, option_type: option_type)
      end

      def resolve_leg_security_id(api_security_id, derivative, use_oc_sec_id:)
        if use_oc_sec_id && valid_security_id?(api_security_id)
          api_security_id.to_s
        elsif derivative
          derivative.security_id.to_s
        end
      end

      def derivative_mismatch?(derivative, strike_bd:, expiry_date_obj:, option_type:)
        return true unless BigDecimal(derivative.strike_price.to_s) == strike_bd
        return true unless derivative.expiry_date == expiry_date_obj
        return true unless derivative.option_type == option_type

        false
      end

      # rubocop:disable-next Metrics/ParameterLists
      def score_and_sort_legs(legs, side:, atm_strike:, atm_range_percent:, flow_scores:, flow_analyzer:, flow_side:,
                              gamma_pressure:, prop_selector:, index_prices:)
        scored = legs.map do |leg|
          flow_score = flow_scores[leg[:strike].to_f] || 1.0
          history = flow_analyzer&.get_history(leg[:strike], flow_side)
          sig = :none
          if history && index_prices
            detector = Options::DeltaAccelerationDetector.new(
              index_prices: index_prices,
              option_prices: [history[:ltp], leg[:ltp]],
              volumes: history[:volume_history] || [leg[:volume]],
              oi: [history[:oi], leg[:oi]]
            )
            sig = detector.signal
          end

          score = calculate_strike_score(
            leg, side, atm_strike, atm_range_percent,
            flow_score: flow_score, gamma_pressure: gamma_pressure,
            prop_selector: prop_selector, acceleration_signal: sig, history: history
          )
          leg.merge(score: score, acceleration_signal: sig)
        end

        scored.sort_by { |l| [-l[:score], l[:distance_from_atm]] }
      end
    end
  end
end
