# frozen_string_literal: true

require 'active_support/core_ext/numeric'

module Smc
  # Builds trade-ready signals (CE/PE buys) using SMC structure + indicators + option chain checks
  #
  # Usage:
  #   gen = Smc::SignalGenerator.new(instrument, interval: '5', mode: :live)
  #   signal = gen.generate
  #
  # Returns nil or a Hash:
  # { type: :ce, strike:, option_symbol:, qty:, spot:, sl_spot:, target_spot:, meta: {} }
  class SignalGenerator
    DEFAULT_ADX_MIN = 18
    DEFAULT_MAX_IV = 60.0
    DEFAULT_VOLUMN_EXPANSION_RATIO = 1.25
    DEFAULT_CAPITAL_PCT = 0.30

    attr_reader :instrument, :series, :interval, :mode, :config

    # instrument: Instrument AR object
    # mode: :live or :backtest
    def initialize(instrument, interval: '5', mode: :live, config: {})
      raise ArgumentError, "Instrument required" unless instrument
      @instrument = instrument
      @interval = interval.to_s
      @mode = mode.to_sym
      @series = instrument.candle_series(interval: interval)
      raise "Empty CandleSeries for #{instrument.symbol_name}" if @series.nil? || @series.candles.empty?

      # merged config defaults and passed config
      default = (AlgoConfig.fetch[:smc] || {}).deep_symbolize_keys
      @config = default.merge(config.deep_symbolize_keys)
    end

    # main entry - returns signal hash or nil
    def generate
      ensure_minimum_data!

      struct = Smc::Structure.new(series, interval: interval)
      bos = struct.break_of_structure
      return nil unless bos # require BOS for meaningful SMC signal

      ob  = struct.order_block(bos)
      fvg = struct.last_fvg

      # Trend strength filters
      supertrend = safe_series_call(:supertrend_signal)
      adx_val = safe_series_call(:adx, 14) || 0.0
      adx_ok = adx_val.to_f >= (config[:adx_min_strength] || DEFAULT_ADX_MIN)

      # volume confirmation
      vol_ok = volume_expansion?(series)

      # require mitigation (tap) OR very strong immediate breakout (liquidity sweep + volume)
      mitigated = struct.mitigated?(ob: ob, fvg: fvg)
      sweep = struct.liquidity_sweep?
      sweep_confirm = (bos[:type] == :bos_bull && sweep[:bull]) || (bos[:type] == :bos_bear && sweep[:bear])

      # require at least one confirmation: mitigation or sweep+volume
      confirmation = mitigated || (sweep_confirm && vol_ok)

      return nil unless confirmation && adx_ok

      # supertrend alignment: prefer matching direction, but allow if ADX strong
      if bos[:type] == :bos_bull
        return nil unless (supertrend == :bull) || adx_ok
        kind = :ce
      else
        return nil unless (supertrend == :bear) || adx_ok
        kind = :pe
      end

      # strike selection via Option::ChainAnalyzer (patched)
      oc = Option::ChainAnalyzer.new(instrument.symbol_name, segment: instrument.exchange_segment)
      atm_info = oc.atm
      return nil unless atm_info
      strike_data = oc.find_strike(atm_info[:strike], type: kind, steps: strike_step_for_iv(oc, atm_info[:strike]))
      return nil unless strike_data

      # IV & liquidity sanity
      iv = strike_data[:iv] || oc.iv_rank(atm_info[:strike])
      max_iv = config[:max_iv] || DEFAULT_MAX_IV
      return nil if iv && iv > max_iv

      unless oc.liquid?(strike_data)
        Rails.logger.info("[Smc::SignalGenerator] Strike not liquid - #{strike_data[:symbol]} (iv=#{iv})")
        return nil
      end

      # compute quantity using Capital::Allocator if present, else single lot
      lot = (strike_data[:lot_size] || instrument.lot_size || 1).to_i
      qty = allocate_qty(strike_data)

      return nil if qty.to_i <= 0

      spot = series.close_last

      # SL and TP defined in spot terms. Runner will translate to option-price based stop if appropriate.
      sl_spot = compute_sp_sl(bos: bos, ob: ob, kind: kind)
      target_spot = compute_target(spot: spot, bos: bos)

      {
        type: kind,
        strike: strike_data[:strike],
        option_symbol: strike_data[:symbol],
        qty: qty,
        lot_size: lot,
        spot: spot,
        sl_spot: sl_spot,
        target_spot: target_spot,
        meta: {
          bos: bos,
          ob: ob,
          fvg: fvg,
          adx: adx_val,
          supertrend: supertrend,
          iv: iv,
          mode: mode,
          generated_at: Time.current
        }
      }
    rescue => e
      Rails.logger.error("[Smc::SignalGenerator] Failed for #{instrument&.symbol_name}: #{e.message}\n#{e.backtrace.first(6).join("\n")}")
      nil
    end

    private

    def ensure_minimum_data!
      if series.nil? || series.candles.size < 20
        raise "Insufficient candle data (need >=20) for #{instrument.symbol_name}"
      end
    end

    def safe_series_call(method, *args)
      return nil unless series.respond_to?(method)
      series.public_send(method, *args)
    rescue StandardError => e
      Rails.logger.debug("[Smc::SignalGenerator] safe_series_call #{method} failed: #{e.message}")
      nil
    end

    # return 0 or 1 step depending on iv
    def strike_step_for_iv(oc, atm)
      iv = oc.iv_rank(atm) || 0
      iv > 35 ? 1 : 0
    end

    # naive quantity allocation: use Capital::Allocator if available, else 1 lot
    def allocate_qty(strike_data)
      if defined?(Capital::Allocator)
        allocation = Capital::Allocator.amount_for(config[:capital_alloc_pct] || DEFAULT_CAPITAL_PCT)
        price = strike_data[:premium] || strike_data[:ltp] || 0.0
        return (strike_data[:lot_size] || instrument.lot_size || 1) if price.to_f <= 0

        qty = (allocation.to_f / price.to_f).to_i
        lot = strike_data[:lot_size] || instrument.lot_size || 1
        (qty / lot) * lot
      else
        strike_data[:lot_size] || instrument.lot_size || 1
      end
    end

    # Compute spot-based stop loss conservative rules
    def compute_sp_sl(bos:, ob:, kind:)
      spot = series.close_last
      if ob
        if ob[:type] == :bull_ob
          [ob[:low] - tick_buffer, bos[:level] * 0.995].compact.min
        elsif ob[:type] == :bear_ob
          [ob[:high] + tick_buffer, bos[:level] * 1.005].compact.max
        else
          spot * (kind == :ce ? 0.998 : 1.002)
        end
      else
        spot * (kind == :ce ? 0.995 : 1.005)
      end
    end

    # target: modest R multiple (configurable)
    def compute_target(spot:, bos:)
      r_mult = config[:r_mult] || 1.5
      # target set as percentage move relative to SL distance; conservative if no SL computed
      spot * (bos[:type] == :bos_bull ? (1 + 0.0075 * r_mult) : (1 - 0.0075 * r_mult))
    end

    def volume_expansion?(series)
      arr = series.candles.last(5).map(&:volume)
      return false if arr.size < 3
      avg = arr[0..-2].sum.to_f / (arr.size - 1)
      arr.last.to_f > avg * (config[:volume_expansion_ratio] || DEFAULT_VOLUMN_EXPANSION_RATIO)
    end

    def tick_buffer
      Smc::Structure.new(series).tick_buffer
    end
  end
end
