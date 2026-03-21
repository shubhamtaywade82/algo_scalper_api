# frozen_string_literal: true

module Options
  # Derives directional chain confirmation from raw option-chain hash (same shape as FlowAnalyzer).
  # Does not call ChainAnalyzer — read-only analysis for permission gating.
  class ChainSignalExtractor
    Result = Struct.new(
      :direction_confidence,
      :direction_hint,
      :oi_confirmation,
      :premium_expansion,
      :pcr,
      :near_expiry_penalty,
      keyword_init: true # rubocop:disable Style/RedundantStructKeywordInit
    )

    def initialize(index_key:, expiry_date:, chain_data:, final_direction:, atm_strike: nil)
      @index_key = index_key.to_s.upcase
      @expiry_date = expiry_date
      @chain_data = chain_data
      @final_direction = final_direction.to_sym
      @atm_strike = atm_strike
    end

    def call
      return neutral_result unless @chain_data && @chain_data[:oc]

      flow = FlowAnalyzer.new(
        index_key: @index_key,
        expiry_date: @expiry_date,
        chain_data: @chain_data
      )
      strong = flow.strong_flow_strikes
      pcr = compute_pcr
      hint = infer_hint(strong, pcr)
      conf = confidence_score(strong, pcr, hint)
      conf *= near_expiry_multiplier

      oi_ok = oi_aligns?(strong, pcr)
      premium_x = premium_expanding?(flow)

      Result.new(
        direction_confidence: conf.round.clamp(0, 100),
        direction_hint: hint,
        oi_confirmation: oi_ok,
        premium_expansion: premium_x,
        pcr: pcr,
        near_expiry_penalty: near_expiry_multiplier < 1.0
      )
    end

    private

    def neutral_result
      Result.new(
        direction_confidence: 0,
        direction_hint: :neutral,
        oi_confirmation: false,
        premium_expansion: false,
        pcr: nil,
        near_expiry_penalty: false
      )
    end

    # PCR = total PE OI / total CE OI (liquid strikes only).
    def compute_pcr
      ce_oi = 0
      pe_oi = 0
      @chain_data[:oc].each_value do |data|
        ce = data['ce'] || data[:ce]
        pe = data['pe'] || data[:pe]
        ce_oi += ce&.dig('oi').to_i
        pe_oi += pe&.dig('oi').to_i
      end
      return nil unless ce_oi.positive?

      (pe_oi.to_f / ce_oi).round(4)
    end

    def infer_hint(strong, pcr)
      ce_top = strong['ce'].first
      pe_top = strong['pe'].first
      ce_s = ce_top&.fetch(:score, 0).to_f
      pe_s = pe_top&.fetch(:score, 0).to_f

      if ce_s > pe_s * 1.1 && pcr.to_f < 1.0
        :bullish
      elsif pe_s > ce_s * 1.1 && pcr.to_f > 1.0
        :bearish
      elsif pcr.to_f > 1.15
        :bullish
      elsif pcr.to_f < 0.85
        :bearish
      else
        :neutral
      end
    end

    def confidence_score(strong, pcr, hint)
      score = 20.0
      score += 30.0 if strong['ce'].any? || strong['pe'].any?
      score += 20.0 if pcr&.between?(0.7, 1.4)
      score += 30.0 if hint != :neutral && aligns_hint?(hint)
      score
    end

    def aligns_hint?(hint)
      (@final_direction == :bullish && hint == :bullish) ||
        (@final_direction == :bearish && hint == :bearish)
    end

    def oi_aligns?(strong, pcr)
      return true if aligns_hint?(infer_hint(strong, pcr))

      # Soft confirmation: dominant flow side matches direction
      if @final_direction == :bullish
        strong['ce'].first&.fetch(:score, 0).to_f >= strong['pe'].first&.fetch(:score, 0).to_f
      else
        strong['pe'].first&.fetch(:score, 0).to_f >= strong['ce'].first&.fetch(:score, 0).to_f
      end
    end

    def premium_expanding?(flow)
      strike = resolve_atm_strike
      return false unless strike

      type = @final_direction == :bullish ? 'ce' : 'pe'
      bucket = @chain_data[:oc][strike] || @chain_data[:oc][strike.to_s] || @chain_data[:oc][strike.to_f]
      opt = bucket&.dig(type) || bucket&.dig(type.to_sym)
      return false unless opt

      hist = flow.get_history(strike, type)
      return false unless hist && hist[:ltp].to_f.positive?

      cur = opt['last_price'].to_f
      prev = hist[:ltp].to_f
      pct = ((cur - prev) / prev * 100.0).abs
      threshold = AlgoConfig.fetch.dig(:market_context, :chain_signal_extractor, :premium_move_pct_threshold).to_f
      threshold = 3.0 if threshold <= 0

      pct >= threshold
    rescue StandardError
      false
    end

    def resolve_atm_strike
      return @atm_strike if @atm_strike

      spot = @chain_data[:last_price].to_f
      return nil unless spot.positive? && @chain_data[:oc]

      @chain_data[:oc].keys.min_by { |k| (k.to_f - spot).abs }
    end

    def near_expiry_multiplier
      days = cfg_int(:near_expiry_penalty_days, 1)
      return 1.0 if days <= 0

      exp = @expiry_date
      return 1.0 unless exp

      d = exp.to_date - Time.zone.today
      d = d.to_i if d.respond_to?(:to_i)
      return 0.75 if d <= days

      1.0
    rescue StandardError
      1.0
    end

    def cfg_int(key, default)
      v = AlgoConfig.fetch.dig(:market_context, :chain_signal_extractor, key)
      v.nil? ? default : v.to_i
    end
  end
end
