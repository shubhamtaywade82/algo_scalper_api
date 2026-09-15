# frozen_string_literal: true

require 'concurrent/map'

module Scalp
  # ChainTrailingContext — in-trade option-chain telemetry for the trailing stop.
  #
  # PROBLEM: every chain-derived signal in this stack (OI buildup, IV rank, gamma
  # walls, delta acceleration) is consumed at ENTRY time only. Once the position
  # is live, the trailing system looks at premium PnL and the underlying — never
  # back at the chain — even though the chain keeps describing the contract's
  # actual health: IV collapsing at your own strike, open interest unwinding,
  # fresh writers pinning the strike, convexity accelerating, or a gamma wall
  # (max-OI strike) dead ahead that premium expansion runs into.
  #
  # This service mirrors Live::UnderlyingContextEvaluator (underlying-driven) but
  # is chain-driven. It is consulted by UnifiedExitChecker#evaluate_trailing_stop
  # ONLY once trailing is armed, and feeds back one of:
  #
  #   :exit     own-strike IV collapsed vs entry IV, or spot ran into the gamma
  #             wall in the trade direction while profitable enough to bank
  #   :tighten  OI unwinding at the own strike (fuel draining), or fresh writing
  #             at the strike while the position is not yet profitable
  #   :widen    premium convexity accelerating (underlying move amplifying into
  #             the premium) — let the runner breathe
  #   :hold     chain unavailable / no signal — trailing unchanged
  #
  # Data sources (per evaluation):
  #   * ONE Instrument#fetch_option_chain call — already ~2min Rails.cache-backed
  #     (same path as GreeksDecayExitRule / Signal::Engine#fetch_real_atm_iv), so
  #     no extra per-tick chain fetches.
  #   * Live::TickQuery for the underlying LTP (fresh) to build a short underlying
  #     price history across evaluations for the convexity ratio.
  #   * tracker.iv_at_entry (column) and a meta['scalp_oi_baseline'] baseline
  #     captured on first evaluation for drift comparisons.
  #
  # Cadence: results are TTL-cached per tracker (default 15s) — this runs on the
  # per-tick exit path and must stay cheap between refreshes.
  #
  # Failure contract: any error inside evaluate is logged and degrades to :hold
  # (documented isolation boundary — identical to Live::UnderlyingMonitor's
  # evaluate contract; a telemetry layer must never take the exit path down).
  #
  # Config (config/algo.yml under risk.scalp_exit.chain_context):
  #   chain_context:
  #     enabled: true
  #     eval_ttl_seconds: 15
  #     iv_collapse_pct: 0.15          # own-strike IV drop from entry -> exit
  #     oi_unwind_pct: 0.10            # OI drop from baseline -> tighten
  #     oi_write_pct: 0.15             # OI rise from baseline -> tighten (writing)
  #     oi_write_max_pnl_pct: 0.0      # writing tightens only while pnl <= this
  #     tighten_multiplier: 0.5
  #     convexity_min_ratio: 8.0       # premium return / underlying return -> widen
  #     convexity_widen_multiplier: 1.2
  #     wall_buffer_pct: 0.003         # spot within 0.3% of wall counts as "at wall"
  #     wall_exit_min_peak_pct: 0.02   # bank into the wall only once peak >= 2%
  class ChainTrailingContext
    EVAL_TTL_DEFAULT = 15.0

    DEFAULTS = {
      eval_ttl_seconds: EVAL_TTL_DEFAULT,
      iv_collapse_pct: 0.15,
      oi_unwind_pct: 0.10,
      oi_write_pct: 0.15,
      oi_write_max_pnl_pct: 0.0,
      tighten_multiplier: 0.5,
      convexity_min_ratio: 8.0,
      convexity_widen_multiplier: 1.2,
      wall_buffer_pct: 0.003,
      wall_exit_min_peak_pct: 0.02
    }.freeze

    NUMERIC_PATTERN = /\A-?\d+(\.\d+)?\z/.freeze

    class << self
      # @param tracker [PositionTracker]
      # @param snapshot [Hash] Redis PnL snapshot (ltp, pnl_pct, hwm_pnl)
      # @return [Hash] { action: :exit|:tighten|:widen|:hold, multiplier: Float, reason: String|nil }
      def evaluate(tracker, snapshot)
        return hold_result unless enabled?

        entry = cache_entry_for(tracker.id)
        return entry[:result] if fresh?(entry)

        begin
          result = compute(tracker, snapshot, entry)
        rescue StandardError => e
          Rails.logger.error("[Scalp::ChainTrailingContext] evaluate failed for tracker=#{tracker.id}: #{e.class} - #{e.message}")
          result = hold_result
        end
        # Stamp the TTL even for failures/holds: a persistently broken chain must
        # not retry on every tick — bounded retry rate, one attempt per window.
        entry[:at] = monotonic_now
        entry[:result] = result
        result
      rescue StandardError => e
        # enabled?/cache layer itself failed (e.g. corrupt config document) —
        # hold loudly rather than take the exit path down.
        Rails.logger.error("[Scalp::ChainTrailingContext] pre-check failed: #{e.class} - #{e.message}")
        hold_result
      end

      def reset_cache!
        cache.clear
      end

      # Evict a closed tracker's cache entry (called from Positions::ExitFlow on
      # exit). The class-level map is keyed by tracker id and would otherwise
      # leak an entry per position for the daemon's lifetime.
      def forget(tracker_id)
        cache.delete(tracker_id)
      rescue StandardError => e
        Rails.logger.debug do
          "[Scalp::ChainTrailingContext] forget failed for tracker=#{tracker_id}: #{e.class} - #{e.message}"
        end
      end

      # Honors both the chain_context switch and the parent scalp_exit switch —
      # turning off scalp_exit must turn off chain telemetry too.
      def enabled?
        Scalp::FeeAwareExitTargets.enabled? && chain_cfg[:enabled] != false
      end

      private

      def cache
        @cache ||= Concurrent::Map.new
      end

      def cache_entry_for(tracker_id)
        cache[tracker_id] ||= { at: -Float::INFINITY, result: hold_result,
                                underlying_history: [], premium_history: [] }
      end

      def fresh?(entry)
        (monotonic_now - entry[:at]) < cfg_value(:eval_ttl_seconds)
      end

      def monotonic_now
        Process.clock_gettime(Process::CLOCK_MONOTONIC)
      end

      # rubocop:disable Metrics/AbcSize
      def compute(tracker, snapshot, entry)
        instrument = tracker.instrument
        return hold_result unless instrument

        strike = instrument.strike_price.to_f
        option_type = instrument.option_type.to_s.downcase
        expiry = instrument.expiry_date || tracker.expiry_date
        return hold_result unless strike.positive? && %w[ce pe].include?(option_type) && expiry

        chain = instrument.fetch_option_chain(expiry)
        oc = chain.is_a?(Hash) ? (chain[:oc] || chain['oc']) : nil
        return hold_result unless oc.is_a?(Hash) && !oc.empty?

        spot = chain[:last_price].to_f
        own_leg = own_strike_leg(oc, strike, option_type)
        return hold_result unless own_leg

        pos_data = Positions::ActiveCache.instance.get_by_tracker_id(tracker.id)
        direction = resolve_direction(tracker, pos_data)
        pnl_pct = snapshot[:pnl_pct].to_f
        peak_pct = peak_profit_pct(tracker, snapshot)

        # Exit-grade signals first.
        iv_res = iv_collapse_signal(tracker, own_leg)
        return iv_res if iv_res

        wall_res = direction ? gamma_wall_signal(oc, spot, direction, peak_pct) : nil
        return wall_res if wall_res

        # Degradation signals.
        oi_res = oi_drift_signal(tracker, own_leg, pnl_pct)
        return oi_res if oi_res

        # Convexity: premium move amplifying relative to the underlying.
        widen_res = convexity_signal(pos_data, direction, entry)
        return widen_res if widen_res

        hold_result
      end
      # rubocop:enable Metrics/AbcSize

      # --- signal builders ---------------------------------------------------

      # Own-contract IV collapse vs the entry-time IV snapshot (column).
      def iv_collapse_signal(tracker, own_leg)
        entry_iv = tracker.iv_at_entry.to_f
        current_iv = own_leg['implied_volatility'].to_f
        return nil unless entry_iv.positive? && current_iv.positive?

        drop = (entry_iv - current_iv) / entry_iv
        return nil unless drop >= cfg_value(:iv_collapse_pct)

        exit_result(
          "SCALP_IV_COLLAPSE (own-strike IV #{entry_iv.round(2)} -> #{current_iv.round(2)}, " \
          "drop #{(drop * 100).round(1)}%)"
        )
      end

      # Max-OI strike (gamma wall) dead ahead in the trade direction. Premium
      # expansion typically stalls when spot pins at a high-OI strike — bank the
      # move into the wall instead of giving it back.
      def gamma_wall_signal(oc, spot, direction, peak_pct)
        return nil unless spot.positive?

        wall = wall_ahead(oc, spot, direction)
        return nil unless wall

        distance = direction == :bullish ? (wall - spot) : (spot - wall)
        return nil unless distance <= spot * cfg_value(:wall_buffer_pct)
        return nil unless peak_pct >= cfg_value(:wall_exit_min_peak_pct)

        exit_result(
          "SCALP_GAMMA_WALL_APPROACH (#{direction} wall at #{wall}, spot #{spot.round(2)}, " \
          "peak #{(peak_pct * 100).round(2)}%)"
        )
      end

      # OI drift at the own strike vs the baseline captured on first evaluation.
      # Unwinding = fuel draining (tighten); heavy fresh writing while the
      # position is flat/underwater = writers pinning the strike (tighten).
      def oi_drift_signal(tracker, own_leg, pnl_pct)
        current_oi = own_leg['oi'].to_i
        meta = tracker.meta || {}
        baseline = meta['scalp_oi_baseline']

        if baseline.nil?
          record_oi_baseline(tracker, meta, current_oi)
          return nil
        end

        baseline_oi = baseline.to_i
        return nil unless baseline_oi.positive? && current_oi.positive?

        drift = (current_oi - baseline_oi).to_f / baseline_oi

        if drift <= -cfg_value(:oi_unwind_pct)
          return tighten_result(
            "SCALP_OI_UNWIND (own-strike OI #{baseline_oi} -> #{current_oi}, " \
            "drift #{(drift * 100).round(1)}%)"
          )
        end

        if drift >= cfg_value(:oi_write_pct) && pnl_pct <= cfg_value(:oi_write_max_pnl_pct)
          return tighten_result(
            "SCALP_OI_WRITING (own-strike OI #{baseline_oi} -> #{current_oi}, " \
            "drift #{(drift * 100).round(1)}%, pnl #{(pnl_pct * 100).round(2)}%)"
          )
        end

        nil
      end

      # Premium convexity: the ratio of premium return to underlying return over
      # the short live window. Both series are sampled ONCE PER EVALUATION (TTL
      # cadence) so the two returns span the same window — comparing a per-tick
      # premium return against a per-TTL underlying return made the ratio
      # structurally unreachable (review P1). A strong reading — the underlying
      # move is amplifying into the premium, in the trade's favour — widens the
      # trail so one-tick pullbacks don't shake out a runner.
      #
      # Deliberately NOT Options::DeltaAccelerationDetector: its volume-spike
      # gate needs a volume history we don't keep in-trade, and its directional
      # check is CE-shaped (it would never widen a PE trail).
      #
      # Returns nil when the position direction is unknown — "favourable" is
      # undefined without it, and a guess can widen the wrong trail (review P2:
      # unknown != measured).
      def convexity_signal(pos_data, direction, entry)
        return nil unless direction

        premium_history = entry[:premium_history]
        p_now = pos_data&.price_history&.last.to_f
        premium_history << p_now if p_now.positive?
        premium_history.shift if premium_history.size > 10

        underlying_history = entry[:underlying_history]
        u_now = current_underlying_ltp(pos_data)
        if u_now
          underlying_history << u_now
          underlying_history.shift if underlying_history.size > 10
        end
        return nil unless premium_history.size >= 2 && underlying_history.size >= 2

        p_prev, p_now = premium_history.last(2)
        u_prev, u_last = underlying_history.last(2)
        return nil unless p_prev.to_f.positive? && u_prev.to_f.positive?

        premium_ret = (p_now.to_f - p_prev.to_f) / p_prev.to_f
        underlying_ret = (u_last.to_f - u_prev.to_f) / u_prev.to_f

        favorable = direction == :bullish ? underlying_ret.positive? : underlying_ret.negative?
        return nil unless favorable && premium_ret.positive?
        return nil if underlying_ret.abs < 0.0001 # flat underlying — ratio is noise

        ratio = premium_ret.abs / underlying_ret.abs
        return nil unless ratio >= cfg_value(:convexity_min_ratio)

        widen_result(
          "SCALP_CONVEXITY (ratio #{ratio.round(1)}, premium #{p_prev} -> #{p_now}, " \
          "underlying #{u_prev} -> #{u_last})"
        )
      end

      # --- data helpers ------------------------------------------------------

      # Strike key formats seen across chain producers ("24500.0" canonical from
      # normalize_option_chain_response; defensive alternates per ChainWatchService).
      def own_strike_leg(oc, strike, option_type)
        [strike.to_f.to_s, format('%<v>.6f', v: strike), strike.to_i.to_s].uniq.filter_map do |key|
          leg = oc[key]
          leg.is_a?(Hash) ? leg[option_type] : nil
        end.first
      end

      # Highest-OI strike strictly beyond spot in the trade direction.
      def wall_ahead(oc, spot, direction)
        legs = oc.filter_map do |strike_key, data|
          next unless data.is_a?(Hash)

          leg = direction == :bullish ? data['ce'] : data['pe']
          strike = strike_key.to_f
          oi = leg.is_a?(Hash) ? leg['oi'].to_i : 0
          next unless oi.positive?

          beyond = direction == :bullish ? (strike > spot) : (strike < spot)
          { strike: strike, oi: oi } if beyond
        end
        return nil if legs.empty?

        legs.max_by { |l| l[:oi] }[:strike]
      end

      def current_underlying_ltp(pos_data)
        segment = pos_data&.underlying_segment
        security_id = pos_data&.underlying_security_id
        return nil if segment.blank? || security_id.blank?

        Live::TickQuery.for_security(segment: segment, security_id: security_id)&.ltp&.to_f
      end

      def peak_profit_pct(tracker, snapshot)
        entry_value = tracker.entry_price.to_f * tracker.quantity.to_f
        return 0.0 unless entry_value.positive?

        snapshot[:hwm_pnl].to_f / entry_value
      end

      # Same normalization contract as UnderlyingContextEvaluator#resolve_position_direction,
      # but unknown stays UNKNOWN (nil) instead of guessing :bullish — the
      # direction-dependent signals (gamma wall, convexity) are skipped rather
      # than computed against a fabricated direction (review P2: unknown !=
      # measured; a wrong guess can bank profit at a wall that isn't ahead).
      def resolve_direction(tracker, pos_data)
        raw = pos_data&.position_direction.presence ||
              (tracker.respond_to?(:direction) ? tracker.direction.presence : nil) ||
              tracker.meta&.dig('direction')

        case raw.to_s.downcase
        when 'long_pe', 'bearish', 'put' then :bearish
        when 'long_ce', 'bullish', 'call' then :bullish
        else nil
        end
      end

      def record_oi_baseline(tracker, _meta, current_oi)
        return unless current_oi.positive?
        return unless tracker.respond_to?(:update_column)

        # Merge into the freshest meta we have instead of blind-writing the
        # stale hash: update_column is last-write-wins on the whole blob and
        # another writer may have stamped a different key since this was read
        # (review P3 - once per tracker, but a merge is safer).
        # Skip validations on purpose: telemetry path, runs every few seconds.
        fresh_meta = (tracker.meta || {}).merge('scalp_oi_baseline' => current_oi)
        tracker.update_column(:meta, fresh_meta) # rubocop:disable Rails/SkipsModelValidations
      end

      # --- results / config --------------------------------------------------

      def hold_result
        { action: :hold, multiplier: 1.0, reason: nil }
      end

      def exit_result(reason)
        { action: :exit, multiplier: 1.0, reason: reason }
      end

      def tighten_result(reason)
        { action: :tighten, multiplier: cfg_value(:tighten_multiplier), reason: reason }
      end

      def widen_result(reason)
        { action: :widen, multiplier: cfg_value(:convexity_widen_multiplier), reason: reason }
      end

      def chain_cfg
        AlgoConfig.fetch.dig(:risk, :scalp_exit, :chain_context) || {}
      end

      # Strict numeric read: absent key -> documented default; garbage raises.
      def cfg_value(key)
        raw = chain_cfg[key]
        return DEFAULTS[key].to_f if raw.nil?
        return raw.to_f if raw.is_a?(Numeric)
        return raw.to_f if raw.is_a?(String) && raw.match?(NUMERIC_PATTERN)

        raise Errors::ConfigurationError,
              "risk.scalp_exit.chain_context.#{key} must be numeric (got #{raw.inspect})"
      end
    end
  end
end
