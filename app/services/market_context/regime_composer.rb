# frozen_string_literal: true

module MarketContext
  # Composes MarketRegimeDetector + structure/volatility/participation into a RegimeSnapshot.
  class RegimeComposer
    DEFAULT_WEIGHTS = {
      trending_structure: 20,
      displacement: 20,
      vwap_not_chop: 15,
      strong_strength: 15,
      volatility_ok: 10,
      participation_high: 10,
      legacy_confidence: 10
    }.freeze

    def initialize(series:, index_key: nil)
      @series = series
      @index_key = index_key
    end

    def call
      legacy = MarketRegimeDetector.new(@series).detect
      structure = StructureAnalyzer.new(series: @series).call
      volatility = VolatilityAnalyzer.new(series: @series).call
      participation = ParticipationAnalyzer.new(series: @series).call

      structure_label = resolve_structure(legacy[:regime].to_s, structure)
      strength_label = resolve_strength(structure.strength, legacy)
      vol_state = map_volatility(volatility.state, legacy)

      raw = {
        legacy: legacy,
        structure: {
          trend: structure.trend,
          strength: structure.strength,
          displacement: structure.displacement,
          vwap_behavior: structure.vwap_behavior
        },
        volatility: { state: volatility.state, atr: volatility.atr, range_ratio: volatility.range_ratio },
        participation: { level: participation.level, volume_ratio: participation.volume_ratio }
      }

      score = compute_conviction(
        structure_label,
        structure,
        volatility,
        participation,
        legacy
      )

      RegimeSnapshot.new(
        structure: structure_label,
        strength: strength_label,
        volatility_state: vol_state,
        participation: participation.level,
        conviction_score: [[score, 100].min, 0].max,
        displacement: structure.displacement,
        legacy_regime: legacy[:regime].to_s,
        legacy_confidence: legacy[:confidence].to_f,
        raw: raw
      )
    end

    private

    def weights
      w = AlgoConfig.fetch.dig(:market_context, :regime_scoring, :weights)
      return DEFAULT_WEIGHTS unless w.is_a?(Hash)

      DEFAULT_WEIGHTS.merge(w.symbolize_keys)
    rescue StandardError
      DEFAULT_WEIGHTS
    end

    def resolve_structure(legacy_regime, structure)
      case legacy_regime
      when 'CHOPPY'
        :chop
      when 'RANGING'
        :range
      when 'TRENDING_UP'
        :bullish_trend
      when 'TRENDING_DOWN'
        :bearish_trend
      else
        map_from_price_structure(structure.trend)
      end
    end

    def map_from_price_structure(trend)
      case trend
      when :bullish then :bullish_trend
      when :bearish then :bearish_trend
      else :range
      end
    end

    def resolve_strength(struct_strength, legacy)
      return :weak if legacy[:regime].to_s == 'INSUFFICIENT_DATA'

      adx = legacy.dig(:metrics, :adx_value).to_f
      return :strong if struct_strength == :strong && adx >= 40.0
      return :moderate if struct_strength == :moderate || adx >= 30.0

      :weak
    end

    def map_volatility(vol_state, legacy)
      return :exhausted_high if vol_state == :exhausted_high

      iv = legacy.dig(:metrics, :volatility_regime).to_s
      return :exhausted_high if iv == 'HIGH_VOL' && vol_state == :high

      case vol_state
      when :high then :high
      when :low then :low
      else :normal
      end
    end

    def compute_conviction(structure_label, structure, volatility, participation, legacy)
      w = weights
      score = 0.0

      if %i[bullish_trend bearish_trend].include?(structure_label)
        score += w[:trending_structure].to_f
      end

      score += w[:displacement].to_f if structure.displacement
      score += w[:vwap_not_chop].to_f if structure.vwap_behavior != :chop && structure.vwap_behavior != :around
      score += w[:strong_strength].to_f if structure.strength == :strong
      score += w[:volatility_ok].to_f if %i[normal high low].include?(volatility.state) && volatility.state != :exhausted_high
      score += w[:participation_high].to_f if participation.level == :high

      conf = legacy[:confidence].to_f
      score += (conf / 100.0) * w[:legacy_confidence].to_f if conf.positive?

      score.round.clamp(0, 100)
    end
  end
end
