# frozen_string_literal: true

module Smc
  # Reinterprets existing SMC + AVRZ outputs into hierarchical permission levels.
  #
  # IMPORTANT:
  # - This MUST NOT loosen SMC/AVRZ detection rules.
  # - It only changes how conservative outputs (often :no_trade) are *used*.
  #
  # Permission levels:
  # - :blocked         => absolute block (no execution)
  # - :execution_only  => 1-lot, micro-execution only (scalping allowed, no scaling)
  # - :scale_ready     => scaling allowed up to 2-3 lots (needs 1m momentum confirmation)
  # - :full_deploy     => full deployment allowed (rare, scale to max)
  class PermissionResolver < ApplicationService
    Result = Struct.new(
      :permission,
      :bias,
      :max_lots,
      :execution_mode,
      :reasons,
      :entry_signal,
      keyword_init: true
    )

    DEFAULTS = {
      blocked:        { max_lots: 0, execution_mode: :none },
      execution_only: { max_lots: 1, execution_mode: :scalp_only },
      scale_ready:    { max_lots: 3, execution_mode: :scale_allowed },
      full_deploy:    { max_lots: 4, execution_mode: :full_deploy }
    }.freeze

    def initialize(htf:, mtf:, ltf:, avrz:)
      @htf = normalize_context(htf)
      @mtf = normalize_context(mtf)
      @ltf = normalize_context(ltf)
      @avrz = normalize_avrz(avrz)
    end

    def call
      bias = htf_bias(@htf)
      unless bias.in?(%i[bullish bearish])
        return build(:blocked, bias: :neutral, reasons: ['HTF bias neutral'])
      end

      if htf_trend(@htf) == :range
        return build(:blocked, bias: bias, reasons: ['HTF structure in range'])
      end

      unless mtf_aligns?(bias, @htf, @mtf)
        return build(:blocked, bias: bias, reasons: ['MTF misaligned with HTF'])
      end

      rejection = @avrz[:rejection] == true

      # EXECUTION-ONLY (soft no): structure is valid, timing not present yet.
      unless rejection
        return build(
          :execution_only,
          bias: bias,
          reasons: ['Structure valid but AVRZ timing not confirmed']
        )
      end

      # FULL-DEPLOY (hard yes): strict LTF confluence present (current engine's entry).
      entry_signal = strict_entry_signal(bias, @ltf, rejection: rejection)
      if entry_signal
        return build(
          :full_deploy,
          bias: bias,
          entry_signal: entry_signal,
          reasons: ['AVRZ rejection + LTF confluence confirmed']
        )
      end

      # SCALE-READY (soft yes): timing present, but not strict trigger yet.
      build(
        :scale_ready,
        bias: bias,
        reasons: ['AVRZ rejection present; awaiting strict LTF trigger']
      )
    rescue StandardError => e
      Rails.logger.error("[Smc::PermissionResolver] #{e.class} - #{e.message}")
      build(:blocked, bias: :neutral, reasons: ['Permission resolver error'])
    end

    private

    def build(level, bias:, reasons:, entry_signal: nil)
      defaults = DEFAULTS.fetch(level)
      Result.new(
        permission: level,
        bias: bias,
        max_lots: defaults[:max_lots],
        execution_mode: defaults[:execution_mode],
        reasons: Array(reasons),
        entry_signal: entry_signal
      )
    end

    def normalize_context(ctx)
      return ctx.to_h if ctx.respond_to?(:to_h)
      return ctx if ctx.is_a?(Hash)

      {}
    end

    def normalize_avrz(avrz)
      return avrz.to_h if avrz.respond_to?(:to_h)
      return avrz if avrz.is_a?(Hash)

      {}
    end

    def htf_bias(htf)
      pd = htf[:premium_discount] || {}
      return :bullish if pd[:discount] == true
      return :bearish if pd[:premium] == true

      :neutral
    end

    def htf_trend(htf)
      # Prefer swing_structure; fall back to legacy :structure key.
      (htf[:swing_structure] || htf[:structure] || {})[:trend]&.to_sym
    end

    def mtf_aligns?(bias, htf, mtf)
      htf_trend_value = htf_trend(htf)
      mtf_struct = mtf[:swing_structure] || mtf[:structure] || {}
      mtf_trend_value = mtf_struct[:trend]&.to_sym
      mtf_choch = mtf_struct[:choch] == true

      return true if mtf_choch # allow transitional alignment
      return false unless htf_trend_value && mtf_trend_value

      case bias
      when :bullish then mtf_trend_value == :bullish && htf_trend_value == :bullish
      when :bearish then mtf_trend_value == :bearish && htf_trend_value == :bearish
      else false
      end
    end

    def strict_entry_signal(bias, ltf, rejection:)
      return nil unless rejection

      liq = ltf[:liquidity] || {}
      struct = ltf[:swing_structure] || ltf[:structure] || {}
      choch = struct[:choch] == true

      case bias
      when :bullish
        return :call if choch && liq[:sell_side_taken] == true
      when :bearish
        return :put if choch && liq[:buy_side_taken] == true
      end

      nil
    end
  end
end

