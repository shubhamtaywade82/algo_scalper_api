# frozen_string_literal: true

require 'bigdecimal'
require 'active_support/core_ext/hash'
require 'active_support/core_ext/object/blank'

module Options
  class ChainAnalyzer
    # Result of {.pick_strikes_with_qualification}: non-empty +failure_code+ means hard-block with detail.
    StrikePickResult = Struct.new(:picks, :failure_code, :failure_reason) do
      def success?
        picks.present?
      end
    end

    DEFAULT_DIRECTION = :bullish

    include LegacyEvaluation
    extend LegRanker
    extend StrikeScorer

    class << self
      # Smallest gap between listed strikes.
      # @param strikes [Array<Numeric>] listed strikes (any order)
      # @return [Float] strike step, 50.0 when it cannot be determined
      def strike_interval(strikes)
        gaps = strikes.map(&:to_f).uniq.sort.each_cons(2).map { |low, high| high - low }
        gaps.min || 50.0
      end

      def find_next_expiry(expiry_list)
        return nil unless expiry_list.respond_to?(:each)

        today = Time.zone.today
        parsed = expiry_list.compact.filter_map do |raw|
          case raw
          when Date then raw
          when Time, DateTime, ActiveSupport::TimeWithZone then raw.to_date
          when String
            begin
              Date.parse(raw)
            rescue ArgumentError
              nil
            end
          end
        end

        next_expiry = parsed.select { |date| date >= today }.min
        next_expiry&.strftime('%Y-%m-%d')
      end

      def pick_strikes(index_cfg:, direction:)
        instrument = IndexInstrumentCache.instance.get_or_fetch(index_cfg)
        unless instrument
          Rails.logger.warn("[Options] No instrument found for #{index_cfg[:key]}") if defined?(Rails)
          return []
        end

        expiry_list = instrument.expiry_list
        unless expiry_list&.any?
          Rails.logger.warn("[Options] No expiry list available for #{index_cfg[:key]}") if defined?(Rails)
          return []
        end

        expiry_date = find_next_expiry(expiry_list)
        unless expiry_date
          Rails.logger.warn("[Options] Could not determine next expiry for #{index_cfg[:key]}") if defined?(Rails)
          return []
        end

        chain_data = begin
          instrument.fetch_option_chain(expiry_date)
        rescue StandardError => e
          Rails.logger.warn("[Options] Could not determine next expiry for #{index_cfg[:key]} #{expiry_date}: #{e.message}") if defined?(Rails)
          nil
        end
        unless chain_data
          Rails.logger.warn("[Options] No option chain data for #{index_cfg[:key]} #{expiry_date}") if defined?(Rails)
          return []
        end

        atm_price = chain_data[:last_price]
        unless atm_price
          Rails.logger.warn("[Options] No ATM price available for #{index_cfg[:key]}") if defined?(Rails)
          return []
        end

        side = direction == :bullish ? :ce : :pe
        legs = filter_and_rank_from_instrument_data(
          chain_data[:oc],
          atm: atm_price, side: side, index_cfg: index_cfg,
          expiry_date: expiry_date, instrument: instrument
        )

        legs.first(2).map do |leg|
          leg.slice(:segment, :security_id, :symbol, :strike, :ltp, :iv, :oi, :spread, :lot_size, :instrument_id, :derivative_id)
        end
      end

      # Strike Qualification Layer (context-aware + expected-move hard gate)
      def pick_strikes_with_qualification(index_cfg:, direction:, permission:, expected_spot_move:, momentum_score: nil)
        key = index_cfg[:key]
        instrument = IndexInstrumentCache.instance.get_or_fetch(index_cfg)
        return strike_pick_fail(code: 'no_instrument', reason: 'No instrument found for index', index_key: key) unless instrument

        expiry_list = instrument.expiry_list
        return strike_pick_fail(code: 'no_expiry_list', reason: 'No expiry list available for index', index_key: key) unless expiry_list&.any?

        expiry_date = find_next_expiry(expiry_list)
        return strike_pick_fail(code: 'next_expiry_unknown', reason: 'Could not determine next expiry', index_key: key) unless expiry_date

        chain_data = fetch_safe_chain_data(instrument, expiry_date, key)
        validate_chain_res = validate_option_chain_data(chain_data, expiry_date: expiry_date, key: key)
        return validate_chain_res if validate_chain_res

        spot = chain_data[:last_price]&.to_f
        return strike_pick_fail(code: 'spot_unavailable', reason: 'No spot/last_price on chain', index_key: key) unless spot&.positive?

        expected_move = expected_spot_move.to_f
        unless expected_move.positive?
          return strike_pick_fail(code: 'expected_move_non_positive', reason: 'Expected spot move (ATR) is missing or non-positive', index_key: key)
        end

        execute_strike_qualification(
          chain_data: chain_data, spot: spot, instrument: instrument, index_cfg: index_cfg,
          expiry_date: expiry_date, direction: direction, permission: permission,
          expected_move: expected_move, momentum_score: momentum_score
        )
      rescue StandardError => e
        Rails.logger.error("[Options] pick_strikes_with_qualification failed: #{e.class} - #{e.message}") if defined?(Rails)
        StrikePickResult.new([], 'pick_strikes_exception', "#{e.class}: #{e.message.to_s.truncate(500)}")
      end

      def strike_pick_fail(code:, reason:, index_key: nil)
        suffix = index_key.present? ? " [#{index_key}]" : ''
        StrikePickResult.new([], code.to_s, "#{reason}#{suffix}")
      end

      private

      def fetch_safe_chain_data(instrument, expiry_date, key)
        instrument.fetch_option_chain(expiry_date)
      rescue StandardError => e
        Rails.logger.warn("[Options] Could not fetch option chain for #{key} #{expiry_date}: #{e.class} - #{e.message}") if defined?(Rails)
        nil
      end

      def validate_option_chain_data(chain_data, expiry_date:, key:)
        unless chain_data && chain_data[:oc].is_a?(Hash)
          hint = chain_data.present? ? 'present but invalid :oc' : 'nil chain_data'
          return strike_pick_fail(code: 'chain_data_invalid', reason: "No valid option chain data (#{hint}) for expiry #{expiry_date}", index_key: key)
        end

        if chain_data[:oc].empty?
          return strike_pick_fail(code: 'empty_option_chain', reason: "Option chain is empty for expiry #{expiry_date}", index_key: key)
        end

        nil
      end

      # rubocop:disable-next Metrics/ParameterLists
      def execute_strike_qualification(chain_data:, spot:, instrument:, index_cfg:, expiry_date:, direction:, permission:, expected_move:, momentum_score:)
        key = index_cfg[:key]
        side_sym = direction == :bullish ? :CE : :PE
        oc_side = direction == :bullish ? :ce : :pe
        option_type = side_sym.to_s
        expiry_date_obj = Date.parse(expiry_date)

        filtered_chain = filter_chain_by_db_derivatives(chain_data[:oc], instrument: instrument, expiry_date: expiry_date_obj, option_type: option_type)
        if filtered_chain.empty?
          return strike_pick_fail(code: 'chain_db_mismatch', reason: "No strikes match DB derivatives expiry=#{expiry_date} #{option_type}", index_key: key)
        end

        norm_perm = normalize_permission(permission)
        selection = Options::StrikeQualification::StrikeSelector.new.call(
          index_key: key, side: side_sym, permission: norm_perm, spot: spot,
          option_chain: filtered_chain, trend: direction, momentum_score: momentum_score
        )
        return strike_pick_fail(code: 'strike_selector_blocked', reason: "StrikeSelector: #{selection[:reason]}", index_key: key) unless selection[:ok]

        select_and_validate_pick(
          chain_data: chain_data, spot: spot, instrument: instrument, index_cfg: index_cfg,
          expiry_date: expiry_date, direction: direction, oc_side: oc_side, selection: selection,
          expected_move: expected_move, norm_perm: norm_perm
        )
      end

      def filter_chain_by_db_derivatives(oc_data, instrument:, expiry_date:, option_type:)
        available_strikes_bd = instrument.derivative_contracts.where(
          expiry_date: expiry_date, option_type: option_type
        ).pluck(:strike_price).to_set { |sp| BigDecimal(sp.to_s) }

        oc_data.select do |strike_key, _data|
          available_strikes_bd.include?(BigDecimal(strike_key.to_f.to_s))
        end
      end

      def normalize_permission(permission)
        norm = permission.to_s.downcase.to_sym
        norm == :exit_testing ? :scale_ready : norm
      end

      # rubocop:disable-next Metrics/ParameterLists
      def select_and_validate_pick(chain_data:, spot:, instrument:, index_cfg:, expiry_date:, direction:, oc_side:, selection:, expected_move:, norm_perm:)
        key = index_cfg[:key]
        ctx = build_qualification_context(instrument: instrument, expiry_date: expiry_date, chain_data: chain_data, direction: direction, spot: spot, key: key)
        legs = filter_and_rank_from_instrument_data(
          chain_data[:oc], atm: spot, side: oc_side, index_cfg: index_cfg, expiry_date: expiry_date, instrument: instrument,
                           target_strikes: [selection[:strike].to_f], flow_results: ctx[:flow_results], gamma_pressure: ctx[:gamma_pressure],
                           prop_selector: ctx[:prop_selector], flow_analyzer: ctx[:flow_analyzer], index_prices: ctx[:index_prices]
        )
        used_type = selection[:strike_type]

        if legs.blank? && selection[:strike_type] != :ATM
          legs = filter_and_rank_from_instrument_data(
            chain_data[:oc], atm: spot, side: oc_side, index_cfg: index_cfg, expiry_date: expiry_date, instrument: instrument,
                             target_strikes: [selection[:atm_strike].to_f], flow_results: ctx[:flow_results], gamma_pressure: ctx[:gamma_pressure],
                             prop_selector: ctx[:prop_selector], flow_analyzer: ctx[:flow_analyzer], index_prices: ctx[:index_prices]
          )
          used_type = :ATM
        end

        return strike_pick_fail(code: 'no_legs_after_filter', reason: "No legs after filter (strike #{selection[:strike]}, type #{used_type}, side #{oc_side})", index_key: key) if legs.blank?

        leg = legs.first
        exit_mode = AlgoConfig.run_mode == 'exit_testing'
        return [] if !exit_mode && leg[:score] < 140.0

        pick = leg.slice(:segment, :security_id, :symbol, :ltp, :iv, :oi, :spread, :lot_size, :instrument_id, :derivative_id, :strike)
                  .merge(strike_type: used_type, score: leg[:score], acceleration_signal: leg[:acceleration_signal])

        return StrikePickResult.new([pick], nil, nil) if exit_mode

        val_res = Options::StrikeQualification::ExpectedMoveValidator.new.call(
          index_key: key, strike_type: used_type, permission: norm_perm,
          expected_spot_move: expected_move, option_ltp: pick[:ltp]
        )
        return [] unless val_res[:ok]

        StrikePickResult.new([pick], nil, nil)
      end

      def build_qualification_context(instrument:, expiry_date:, chain_data:, direction:, spot:, key:)
        flow_analyzer = Options::FlowAnalyzer.new(index_key: key, expiry_date: expiry_date, chain_data: chain_data)
        gamma_detector = Options::GammaRampDetector.new(index_key: key, expiry_date: expiry_date, chain_data: chain_data)
        index_series = instrument.candle_series(interval: '1')
        index_prices = index_series&.closes&.last(2) || [spot, spot]

        {
          flow_analyzer: flow_analyzer,
          flow_results: flow_analyzer.strong_flow_strikes,
          gamma_pressure: gamma_detector.gamma_pressure_score(direction: direction),
          prop_selector: Options::PropStrikeSelector.new(spot: spot),
          index_prices: index_prices
        }
      end
    end
  end
end
