# frozen_string_literal: true

module Ai
  module Calibration
    # Assembles the master calibration prompt for the Ollama AI model.
    #
    # Injects:
    # - Structured trade dataset (from DatasetBuilder)
    # - Current AlgoConfig snapshot (SL, TP, trailing, ADX thresholds, regime multipliers)
    # - Dataset meta summary (win rate, exit breakdown)
    #
    # Returns a prompt string suitable for Services::Ai::OllamaClient#generate.
    class PromptBuilder
      def self.call(dataset:)
        new(dataset: dataset).call
      end

      def initialize(dataset:)
        @dataset = dataset
        @symbol  = dataset[:symbol]
        @trades  = dataset[:trades]
        @meta    = dataset[:meta]
      end

      def call
        <<~PROMPT.strip
          #{system_section}

          #{separator}
          INPUT DATA
          #{separator}

          #{trades_section}

          #{config_section}

          #{separator}
          DATASET SUMMARY
          #{separator}

          #{summary_section}

          #{separator}
          CALIBRATION OBJECTIVE
          #{separator}

          #{objective_section}

          #{separator}
          MANDATORY ANALYSIS STEPS (Internal Thinking)
          #{separator}

          #{analysis_section}

          #{separator}
          EXAMPLE OUTPUT (Format and Parameter Names)
          #{separator}

          #{example_section}

          #{separator}
          STRICT OUTPUT RULES
          #{separator}

          #{rules_section}

          #{reasoning_instruction}

          Return ONLY valid JSON that matches the provided schema. No markdown formatting.
        PROMPT
      end

      private

      def example_section
        <<~EXAMPLE.strip
          {
            "internal_reasoning": "Observed high SL hit rate in volatile regimes. Win rate drops 15% when SL is 0.10. Simulating 0.15 SL shows improved retention of winners.",
            "system_diagnosis": {
              "primary_failure": "Stop loss is too tight for current market volatility",
              "secondary_issues": ["Trailing activation triggers too early", "Chop decay on Wednesdays"],
              "most_lossy_regime": "volatile"
            },
            "parameter_changes": [
              {
                "parameter": "sl_pct",
                "current": 0.10,
                "suggested": 0.15,
                "change": "increase",
                "reason": "Reduces noise-based SL hits by 22% in volatile regime",
                "confidence": 0.85
              }
            ],
            "entry_filters": [],
            "exit_improvements": []
          }
        EXAMPLE
      end

      def reasoning_instruction
        <<~REASONING.strip
          INSTRUCTION:
          Before providing the JSON, perform a deep "Chain of Thought" analysis.
          1.  Identify why the biggest losers failed (Entry error? Exit too late? Exit too early?).
          2.  Look for correlation between win rate and time of day or regime.
          3.  Simulate how changing SL/TP/Trailing would have affected those specific trades.
          4.  Synthesize these findings into the final JSON output.
        REASONING
      end

      def separator
        '----------------------------------------'
      end

      def system_section
        <<~SYSTEM.strip
          You are a quantitative trading calibration engine for an automated options buying system.

          The system trades #{@symbol} weekly expiry options (CE/PE) on Indian indices.
          It uses indicator-based signals (Supertrend, ADX, VWAP), real-time LTP-based exits,
          and "Options Sentiment" (Gamma Ramps, IV Rank, and Theta Risk).

          Your job is to ANALYZE past paper trades and suggest optimal PARAMETER ADJUSTMENTS.

          You MUST:
            - Operate only on the provided data
            - Map every suggestion to an EXISTING config parameter
            - Include a confidence score (0.0 – 1.0) for each suggestion

          You MUST NOT:
            - Predict future prices
            - Suggest discretionary trades
            - Add parameters that don't exist in the current config
            - Overfit to samples < 20 trades
        SYSTEM
      end

      def trades_section
        <<~TRADES.strip
          1. PAPER TRADES (last #{@dataset[:days] || 30} days, #{@trades.size} trades)
             All PnL values are in INR (Indian Rupees).

          #{JSON.pretty_generate(@trades.first(50))}
        TRADES
      end

      def config_section
        config = load_config_snapshot
        <<~CONFIG.strip
          2. CURRENT SYSTEM CONFIGURATION (algo.yml / DB overrides)
          #{JSON.pretty_generate(config)}
        CONFIG
      end

      def load_config_snapshot
        cfg = AlgoConfig.fetch

        # Extract only calibration-relevant keys to keep prompt concise
        risk   = cfg[:risk] || {}
        sizing = cfg[:position_sizing] || {}

        index_cfg = (cfg[:indices] || []).find { |i| i[:key]&.to_s&.upcase == @symbol } || {}
        adx_thresh = index_cfg[:adx_thresholds] || {}

        {
          symbol: @symbol,
          # Risk model
          sl_pct: risk[:sl_pct],
          tp_pct: risk[:tp_pct],
          per_trade_risk_pct: risk[:per_trade_risk_pct],
          # RR profit booking
          target_rr: risk.dig(:rr_profit_booking, :target_rr),
          # Institutional trailing
          trailing_enabled: risk.dig(:institutional_trailing, :enabled),
          trailing_index: risk.dig(:institutional_trailing, @symbol.downcase.to_sym),
          # Direct trailing
          direct_trailing_enabled: sizing.dig(:direct_trailing, :enabled),
          direct_trailing_distance: sizing.dig(:direct_trailing, :distance_pct),
          trailing_activation: sizing.dig(:trailing, :activation_pct),
          trailing_drawdown: sizing.dig(:trailing, :drawdown_pct),
          # Profit floor
          profit_floor_lock_pct: risk.dig(:profit_floor, :lock_pct),
          profit_floor_trail_pct: risk.dig(:profit_floor, :trail_pct),
          # ADX
          primary_adx_min: adx_thresh[:primary_min_strength],
          confirmation_adx_min: adx_thresh[:confirmation_min_strength],
          # Edge failure detector
          rolling_window_size: cfg.dig(:risk, :edge_failure_detector, :rolling_window_size),
          rolling_window_threshold: cfg.dig(:risk, :edge_failure_detector, :rolling_window_threshold_rupees),
          max_consecutive_sls: cfg.dig(:risk, :edge_failure_detector, :max_consecutive_sls),
          # Trade limits
          max_trades_per_day: index_cfg.dig(:trade_limits, :max_trades_per_day),
          global_max_trades: cfg.dig(:trade_limits, :global_max_trades_per_day)
        }.compact
      rescue StandardError => e
        Rails.logger.warn("[PromptBuilder] Failed to load config: #{e.message}")
        { error: 'config_unavailable' }
      end

      def summary_section
        JSON.pretty_generate(@meta)
      end

      def objective_section
        <<~OBJ.strip
          Maximize:
            - Net PnL (primary)
            - Risk-adjusted return (Sharpe-like: PnL / max_drawdown)
            - Win rate (secondary)

          Minimize:
            - Large losses
            - SL hits caused by noise (SL triggered too early)
            - Overtrading in unfavorable regimes
            - Trailing SL cutting winning trades prematurely
        OBJ
      end

      def analysis_section
        <<~ANALYSIS.strip
          1. LOSS CLUSTERING
             Group losing trades by: exit_reason, option_type, time_of_day, signal_direction

          2. ENTRY FAILURE DETECTION
             Identify: entries with low ADX, weak momentum, near-expiry decay, low confidence_score

          3. EXIT INEFFICIENCY
             - SL too tight? (many SL exits before recovery)
             - Trailing cutting winners? (early trail_activation)
             - Missing TP captures? (profitable trades exiting before target)

          4. OPTIONS SENTIMENT ANALYSIS
             - Did high gamma_score (+0.7) lead to explosive winners or slippage-based losers?
             - Does high iv_rank (> 0.8) correlate with SL hits? (If so, suggest wider SL for high IV).
             - Did late-day entries (high theta_risk) outperform or decay?

          5. PARAMETER SENSITIVITY (logical simulation)
             For each parameter change: describe what % of losing trades would have been avoided
             or what % of winning trades would have been captured better.
        ANALYSIS
      end

      def rules_section
        <<~RULES.strip
          - Only suggest changes to parameters that exist in the CURRENT CONFIGURATION above
          - Every suggestion must include: parameter name, current value, suggested value, reason, confidence
          - Confidence must be 0.0–1.0 (float). Use 0.0 if insufficient data.
          - Skip suggestions with confidence < 0.5
          - Minimum 20 trades required for a valid parameter suggestion; otherwise set confidence to 0.0
          - For regime_rules: only valid regimes are "trend", "range", "volatile", "chop_decay", "close_gamma"
          - For actions: only valid values are "disable_entries", "reduce_size", "tighten_sl"
        RULES
      end
    end
  end
end
