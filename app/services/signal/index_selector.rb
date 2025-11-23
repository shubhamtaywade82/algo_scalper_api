# frozen_string_literal: true

module Signal
  # Index selection service for NEMESIS V3
  # Computes trend_score per index using TrendScorer, picks best index,
  # applies thresholds and tie-breakers
  class IndexSelector
    DEFAULT_MIN_TREND_SCORE = 15.0

    attr_reader :config, :min_trend_score

    def initialize(config: {})
      @config = config
      @min_trend_score = config[:min_trend_score] || DEFAULT_MIN_TREND_SCORE
    end

    # Select the best index based on trend scores
    # @return [Hash, nil] { index_key: :NIFTY, trend_score: 20.0, reason: "..." } or nil
    def select_best_index
      indices = AlgoConfig.fetch[:indices]
      return nil unless indices.is_a?(Array) && indices.any?

      scored_indices = score_all_indices(indices)
      return nil if scored_indices.empty?

      # Filter by minimum trend score
      qualified = scored_indices.select { |idx| idx[:trend_score] >= @min_trend_score }
      return nil if qualified.empty?

      # Apply tie-breakers and select best
      best = apply_tie_breakers(qualified)

      {
        index_key: best[:index_key],
        trend_score: best[:trend_score],
        breakdown: best[:breakdown],
        reason: best[:reason]
      }
    rescue StandardError => e
      Rails.logger.error("[IndexSelector] Error selecting best index: #{e.class} - #{e.message}")
      nil
    end

    private

    # Score all indices using TrendScorer
    # @param indices [Array<Hash>] Array of index configurations
    # @return [Array<Hash>] Array of { index_key, trend_score, breakdown, instrument }
    def score_all_indices(indices)
      indices.filter_map do |index_cfg|
        index_key = index_cfg[:key] || index_cfg['key']
        next unless index_key

        instrument = IndexInstrumentCache.instance.get_or_fetch(index_key: index_key.to_sym)
        next unless instrument

        # Get timeframes from config or use defaults
        primary_tf = @config[:primary_tf] || '1m'
        confirmation_tf = @config[:confirmation_tf] || '5m'

        scorer = TrendScorer.new(
          instrument: instrument,
          primary_tf: primary_tf,
          confirmation_tf: confirmation_tf
        )

        result = scorer.compute_trend_score
        next unless result && result[:trend_score]

        {
          index_key: index_key.to_sym,
          trend_score: result[:trend_score],
          breakdown: result[:breakdown],
          instrument: instrument
        }
      rescue StandardError => e
        Rails.logger.warn("[IndexSelector] Failed to score #{index_key}: #{e.class} - #{e.message}")
        nil
      end
    end

    # Apply tie-breakers to select best index from qualified candidates
    # @param qualified [Array<Hash>] Qualified indices (already filtered by min_trend_score)
    # @return [Hash] Best index with reason
    def apply_tie_breakers(qualified)
      return qualified.first if qualified.size == 1

      # Sort by trend_score (descending)
      sorted = qualified.sort_by { |idx| -idx[:trend_score] }

      # If clear winner (score difference >= 2.0), return it
      if sorted.size >= 2 && (sorted[0][:trend_score] - sorted[1][:trend_score]) >= 2.0
        return add_reason(sorted[0], 'highest_trend_score')
      end

      # Otherwise, apply tie-breakers
      best = sorted.first
      tie_breakers = sorted.select { |idx| (best[:trend_score] - idx[:trend_score]).abs < 2.0 }

      # Tie-breaker 1: Recent performance (momentum from PA score)
      best = break_tie_by_momentum(tie_breakers, best) || best

      # Tie-breaker 2: Liquidity (ADX strength from IND score)
      best = break_tie_by_liquidity(tie_breakers, best) || best

      add_reason(best, 'trend_score_with_tie_breakers')
    end

    # Break tie by momentum (higher PA score = better momentum)
    def break_tie_by_momentum(candidates, current_best)
      return current_best if candidates.empty?

      candidates_with_pa = candidates.map do |candidate|
        pa_score = candidate[:breakdown]&.dig(:pa) || 0
        [candidate, pa_score]
      end

      sorted = candidates_with_pa.sort_by { |_c, pa| -pa }
      best_pa = sorted.first&.last || 0
      current_pa = current_best[:breakdown]&.dig(:pa) || 0

      best_pa > current_pa ? sorted.first&.first : current_best
    end

    # Break tie by liquidity (higher ADX/IND score = better liquidity/trend strength)
    def break_tie_by_liquidity(candidates, current_best)
      return current_best if candidates.empty?

      candidates_with_ind = candidates.map do |candidate|
        ind_score = candidate[:breakdown]&.dig(:ind) || 0
        [candidate, ind_score]
      end

      sorted = candidates_with_ind.sort_by { |_c, ind| -ind }
      best_ind = sorted.first&.last || 0
      current_ind = current_best[:breakdown]&.dig(:ind) || 0

      best_ind > current_ind ? sorted.first&.first : current_best
    end

    # Add reason to index hash
    def add_reason(index_hash, reason_type)
      index_hash.merge(reason: reason_type)
    end
  end
end
