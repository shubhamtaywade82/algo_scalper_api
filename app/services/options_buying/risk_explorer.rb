# frozen_string_literal: true

module OptionsBuying
  # Pre-deploy EV & risk report for long-gamma intraday options buying.
  # Combines config SL/TP, position limits, historical ATM variance, and realized segment stats.
  class RiskExplorer
    def self.call(index_key:, weeks: 8, win_probability: nil, reward_multiple: nil)
      new(index_key: index_key, weeks: weeks, win_probability: win_probability,
          reward_multiple: reward_multiple).call
    end

    def initialize(index_key:, weeks:, win_probability:, reward_multiple:)
      @index_key = index_key.to_s.upcase
      @weeks = weeks.to_i.clamp(1, 24)
      @win_probability = win_probability
      @reward_multiple = reward_multiple
    end

    def call
      risk = risk_config
      limits = position_limits
      historical = historical_context(risk)
      realized = realized_context
      win_p = resolved_win_probability(historical, realized, risk)

      {
        index_key: @index_key,
        generated_at: Time.current.iso8601,
        formula: 'EV = (P_win × R) - (P_loss × 1)',
        risk_config: risk,
        position_limits: limits,
        capital: capital_snapshot,
        scenario: scenario_payload(win_p, risk),
        grid: ExpectedValueModel.grid,
        historical: historical,
        realized: realized,
        theta_churn: theta_churn_assessment(historical),
        deploy_readiness: deploy_readiness(win_p, risk, historical, realized)
      }
    rescue StandardError => e
      Rails.logger.error("[OptionsBuying::RiskExplorer] #{@index_key} #{e.class} - #{e.message}")
      nil
    end

    private

    def risk_config
      cfg = AlgoConfig.fetch[:risk] || {}
      sl = cfg[:sl_pct].to_f
      tp = cfg[:tp_pct].to_f
      r = @reward_multiple.presence || ExpectedValueModel.reward_multiple(sl_pct: sl, tp_pct: tp)

      {
        sl_pct: sl,
        tp_pct: tp,
        reward_multiple: r,
        break_even_win_rate: ExpectedValueModel.break_even_win_rate(reward_multiple: r),
        per_trade_risk_pct: cfg[:per_trade_risk_pct]
      }
    end

    def position_limits
      idx = index_config || {}
      {
        capital_alloc_pct: idx[:capital_alloc_pct],
        max_trades_per_day: idx.dig(:trade_limits, :max_trades_per_day) || idx[:max_trades_per_day],
        max_same_side: idx[:max_same_side],
        max_concurrent_per_index: idx[:max_concurrent_per_index],
        cooldown_sec: idx[:cooldown_sec]
      }
    end

    def capital_snapshot
      balance = Capital::Allocator.available_cash.to_f
      policy = Capital::Allocator.deployment_policy(balance)

      {
        available_cash_rupees: balance.round(2),
        paper_mode: AlgoConfig.fetch.dig(:paper_trading, :enabled) == true,
        deployment_policy: policy
      }
    rescue StandardError => e
      Rails.logger.warn("[OptionsBuying::RiskExplorer] capital_snapshot: #{e.message}")
      { available_cash_rupees: nil, paper_mode: nil, deployment_policy: nil }
    end

    def scenario_payload(win_probability, risk)
      p_win = win_probability.to_f.clamp(0.0, 1.0)
      r = risk[:reward_multiple].to_f
      ev = ExpectedValueModel.ev(win_probability: p_win, reward_multiple: r)

      {
        win_probability: p_win.round(4),
        reward_multiple: r,
        expected_value: ev,
        positive_edge: ev.positive?
      }
    end

    def resolved_win_probability(historical, realized, risk)
      return @win_probability.to_f.clamp(0.0, 1.0) if @win_probability.present?

      estimate = historical.dig(:blended, :target_hit_rate) ||
                 realized.dig(:all_segments, :win_rate)
      return estimate.to_f if estimate.present?

      risk[:break_even_win_rate].to_f + 0.10
    end

    def historical_context(risk)
      analyzer = HistoricalOptionsAnalyzer.new(@index_key, weeks: @weeks)
      raw = analyzer.analyze
      return { available: false, error: raw[:error] } if raw.is_a?(Hash) && raw[:error].present?

      ce_cycles = Array(raw[:cycles]).filter_map { |c| c[:ce] }
      pe_cycles = Array(raw[:cycles]).filter_map { |c| c[:pe] }
      ce_stats = side_stats(ce_cycles, risk)
      pe_stats = side_stats(pe_cycles, risk)

      {
        available: true,
        weeks: @weeks,
        ce: ce_stats,
        pe: pe_stats,
        blended: blend_side_stats(ce_stats, pe_stats)
      }
    rescue StandardError => e
      Rails.logger.warn("[OptionsBuying::RiskExplorer] historical_context: #{e.message}")
      { available: false, error: e.message }
    end

    def side_stats(cycles, risk)
      return nil if cycles.empty?

      tp_threshold = (risk[:tp_pct].to_f * 100.0).round(2)
      sl_threshold = -(risk[:sl_pct].to_f * 100.0).round(2)
      n = cycles.size

      target_hits = cycles.count { |c| c[:max_gain_pct].to_f >= tp_threshold }
      stop_touches = cycles.count { |c| c[:max_loss_pct].to_f <= sl_threshold }
      positive_close = cycles.count { |c| c[:open_to_close_pct].to_f.positive? }

      avg_open_to_close = (cycles.sum { |c| c[:open_to_close_pct].to_f } / n).round(2)
      avg_max_gain = (cycles.sum { |c| c[:max_gain_pct].to_f } / n).round(2)
      avg_max_loss = (cycles.sum { |c| c[:max_loss_pct].to_f } / n).round(2)

      target_hit_rate = (target_hits.to_f / n).round(4)
      stop_touch_rate = (stop_touches.to_f / n).round(4)
      positive_close_rate = (positive_close.to_f / n).round(4)

      {
        sample_weeks: n,
        target_hit_rate: target_hit_rate,
        stop_touch_rate: stop_touch_rate,
        positive_close_rate: positive_close_rate,
        avg_open_to_close_pct: avg_open_to_close,
        avg_max_gain_pct: avg_max_gain,
        avg_max_loss_pct: avg_max_loss,
        expected_value_at_config_rr: ExpectedValueModel.ev(
          win_probability: target_hit_rate,
          reward_multiple: risk[:reward_multiple]
        )
      }
    end

    def blend_side_stats(ce_stats, pe_stats)
      stats = [ce_stats, pe_stats].compact
      return nil if stats.empty?

      n = stats.sum { |s| s[:sample_weeks].to_i }
      weighted_hit = stats.sum { |s| s[:target_hit_rate].to_f * s[:sample_weeks].to_i } / n
      weighted_close = stats.sum { |s| s[:positive_close_rate].to_f * s[:sample_weeks].to_i } / n

      {
        sample_weeks: n,
        target_hit_rate: weighted_hit.round(4),
        positive_close_rate: weighted_close.round(4)
      }
    end

    def realized_context
      regimes = %w[S1 S2 S3 S4]
      segments = regimes.filter_map do |regime|
        stats = Trading::SegmentExpectancyAnalyzer.instance.segment_stats(index_key: @index_key, regime: regime)
        next if stats.blank?

        stats.merge(regime: regime)
      end

      aggregate = if segments.any?
                    sizes = segments.sum { |s| s[:sample_size].to_i }
                    wins = segments.sum { |s| s[:win_rate].to_f * s[:sample_size].to_i }
                    {
                      sample_size: sizes,
                      win_rate: sizes.positive? ? (wins / sizes).round(4) : nil,
                      expectancy_rupees: weighted_expectancy(segments)
                    }
                  end

      { segments: segments, all_segments: aggregate }
    rescue StandardError => e
      Rails.logger.warn("[OptionsBuying::RiskExplorer] realized_context: #{e.message}")
      { segments: [], all_segments: nil, error: e.message }
    end

    def weighted_expectancy(segments)
      total = segments.sum { |s| s[:sample_size].to_i }
      return nil unless total.positive?

      weighted = segments.sum { |s| s[:expectancy_rupees].to_f * s[:sample_size].to_i }
      (weighted / total).round(2)
    end

    def theta_churn_assessment(historical)
      return { risk: 'unknown', message: 'Historical ATM data unavailable' } unless historical[:available]

      blended = historical[:blended]
      return { risk: 'unknown', message: 'Insufficient historical cycles' } if blended.blank?

      close_rate = blended[:positive_close_rate].to_f
      avg_oc = [historical.dig(:ce, :avg_open_to_close_pct), historical.dig(:pe, :avg_open_to_close_pct)]
               .compact
      avg_churn = avg_oc.any? ? (avg_oc.sum / avg_oc.size).round(2) : 0.0

      if close_rate < 0.40 || avg_churn.negative?
        {
          risk: 'elevated',
          message: 'Sideways/chop: low positive close rate or negative avg open-to-close — theta decay likely',
          positive_close_rate: close_rate,
          avg_open_to_close_pct: avg_churn
        }
      else
        {
          risk: 'moderate',
          message: 'Historical ATM weeks show enough directional follow-through for intraday long gamma',
          positive_close_rate: close_rate,
          avg_open_to_close_pct: avg_churn
        }
      end
    end

    def deploy_readiness(win_p, risk, historical, realized)
      ev = ExpectedValueModel.ev(win_probability: win_p, reward_multiple: risk[:reward_multiple])
      conservative = [win_p, risk[:break_even_win_rate].to_f + 0.05].min
      conservative_ev = ExpectedValueModel.ev(
        win_probability: conservative,
        reward_multiple: risk[:reward_multiple]
      )

      {
        expected_value: ev,
        positive_edge: ev.positive?,
        conservative_win_probability: conservative.round(4),
        conservative_expected_value: conservative_ev,
        conservative_positive_edge: conservative_ev.positive?,
        historical_data_available: historical[:available] == true,
        realized_sample_size: realized.dig(:all_segments, :sample_size)
      }
    end

    def index_config
      Array(AlgoConfig.fetch[:indices]).find do |cfg|
        (cfg[:key] || cfg['key']).to_s.upcase == @index_key
      end
    rescue StandardError
      nil
    end
  end
end
