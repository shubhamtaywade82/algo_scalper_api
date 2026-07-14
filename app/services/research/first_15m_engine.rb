# frozen_string_literal: true

module Research
  class First15mEngine
    # Runs the event-centric NIFTY first-15-minute research pipeline (V5).
    # @param symbol [String] 'NIFTY'
    # @param lookback_days [Integer] Number of days to analyze
    # @param target_points [Numeric] Target points for ORB continuation
    # @param output_dir [String] Directory path to save reports
    # @return [Hash] Compiled aggregate report
    def self.run(symbol: "NIFTY", lookback_days: 90, target_points: 50.0, output_dir: "data/research")
      Rails.logger.info("[Research::First15mEngine] Initializing research V5 for #{symbol} (lookback: #{lookback_days} days)")

      # 1. Fetch NIFTY underlying daily data
      days_data = Research::MarketDataFetcher.run(symbol: symbol, lookback_days: lookback_days, strict: true)
      if days_data.empty?
        Rails.logger.error("[Research::First15mEngine] No daily market data found. Exiting.")
        return {}
      end

      # 2. Extract trade events (V5 Event-centric model - supports multiple events per day)
      trades = []
      skipped_days = 0

      days_data.each do |day|
          # Segment the day into distinct opening auction events (breakouts/breakdowns/reversals)
          opps = Research::EventSegmenter.segment(day, target_points: target_points)
          next if opps.empty?

          day_atm_missing = false

          opps.each do |opp|
            option_type = opp[:breakout_type] == :bullish ? "CE" : "PE"

            # Calculate Ignition metrics (first 3 minutes from breakout entry)
            entry_idx = opp[:entry_index]
            candles_3m = day[:underlying_candles][entry_idx..(entry_idx + 3)]
            nifty_ign_pts = 0.0
            if candles_3m && candles_3m.size >= 4
              nifty_ign_pts = candles_3m[3][:close] - candles_3m[0][:open]
            end
            opp[:ignition] = {
              start_time: opp[:entry_time],
              nifty_ignition_points: nifty_ign_pts.round(2),
              ignition_velocity: (nifty_ign_pts / 3.0).round(2)
            }

            # Classify Market Regime for the day
            opp[:prev_day_close] = day[:prev_day_close]
            opp[:prev_day_high] = day[:prev_day_high]
            opp[:prev_day_low] = day[:prev_day_low]
            opp[:underlying_candles] = day[:underlying_candles]
            regime = Research::RegimeClassifier.classify(opp)
            opp[:regime] = regime

            # Predict Archetype at entry moment (no lookahead leakage)
            opp[:predicted_archetype] = Research::AuctionArchetypeClassifier.predict(opp, opp[:entry_index])

            # V7 Context Layer (Global Regimes, Expiries, India VIX)
            opp[:context] = {
              india_vix: day[:india_vix] || 14.5,
              weekly_expiry: day[:weekly_expiry] || (day[:date].wday == 4),
              monthly_expiry: day[:monthly_expiry] || false,
              us_overnight_change: day[:us_overnight_change] || 0.0,
              sector_breadth: day[:sector_breadth] || 0.5
            }

            # Resolve strike candidates (ATM-2, ATM-1, ATM, ATM+1, ATM+2)
            spot_open = day[:underlying_candles].first[:open]
            candidates = Research::StrikeResolver.candidates(
              symbol: symbol,
              spot: spot_open,
              option_type: option_type,
              max_distance: 2
            )

            # Analyze option expansion and exits for each candidate strike
            opp[:strikes] = {}
            atm_option_candles = nil

            candidates.each do |cand|
              label = cand[:strike_label]
              actual_strike = cand[:actual_strike]

              # Load or simulate option candles for this specific strike label
              option_candles = Research::MarketDataFetcher.load_or_simulate_options(
                symbol,
                option_type,
                actual_strike,
                day[:date],
                day[:underlying_candles],
                strike_label: label,
                strict: true
              )

              next if option_candles.empty?
              atm_option_candles = option_candles if label == "ATM"

              # Measure future expansion/MFE/MAE/PES
              expansion_ctx = Research::OptionExpansionAnalyzer.analyze(
                option_candles,
                day[:underlying_candles],
                opp,
                label
              )

              next if expansion_ctx.empty?

              # Simulate exit rules on this strike (now includes lost profit / retention ratio V5)
              exit_ctx = Research::ExitCaptureAnalyzer.run(
                day[:underlying_candles],
                option_candles,
                opp,
                expansion_ctx
              )

              # Trace option lifecycle phases (V4)
              lifecycle = Research::LifecyclePhases.trace(
                option_candles,
                day[:underlying_candles],
                opp,
                expansion_ctx
              )

              opp[:strikes][label] = expansion_ctx.merge(
                exits: exit_ctx,
                lifecycle_phases: lifecycle
              )
            end

            # Skip trade opportunity if we failed to fetch/simulate ATM strike
            unless opp[:strikes].key?("ATM") && atm_option_candles
              day_atm_missing = true
              next
            end

            # Calculate Expected Opportunity Score (EOS V5) for the ATM contract
            opp[:expected_opportunity_score] = Research::OpportunityScorer.score(opp[:strikes]["ATM"])

            # Trace option lifecycle on trade opportunity context (ATM option lifecycle)
            opp[:lifecycle_phases] = opp[:strikes]["ATM"][:lifecycle_phases]

            # Run Negative Research Attribution on failed breakouts
            opp[:failure_reason] = Research::NegativeResearch.analyze(
              day[:underlying_candles],
              atm_option_candles,
              opp,
              opp[:strikes]["ATM"],
              regime
            )

            trades << opp
          end

          skipped_days += 1 if day_atm_missing
      rescue StandardError => e
          Rails.logger.error("[Research::First15mEngine] Failed to analyze trade events on #{day[:date]}: #{e.class} - #{e.message}")
          Rails.logger.error(e.backtrace.first(10).join("\n"))
      end

      Rails.logger.info("[Research::First15mEngine] Simulated #{days_data.size - skipped_days} of #{days_data.size} days (#{skipped_days} skipped: no real option data).")

      return {} if trades.empty?

      # 3. V5 Non-linear & Linear Feature Importance, Resampling and Walk-Forward validations
      correlations = Research::FeatureImportance.analyze(trades, strike_label: "ATM")
      nonlinear_importance = Research::NonlinearFeatureImportance.analyze(trades, strike_label: "ATM")
      validation_reports = Research::StatisticalValidator.run(trades, strike_label: "ATM")

      # Group and tally failed breakout reasons
      negative_analysis = trades.select { |t| t[:failed] }
                                .group_by { |t| t[:failure_reason] }
                                .transform_values(&:size)

      # Group and tally auction archetypes
      archetype_analysis = trades.group_by { |t| t[:archetype] }
                                 .transform_values(&:size)

      # 4. Save the run inside the Research Data Warehouse (SQLite)
      Research::DataWarehouse.save_run(
        trades,
        correlations,
        nonlinear_importance,
        Research::HypothesisEngine.run(trades)
      )

      # 5. Generate Reports
      Research::ResearchReportGenerator.run(
        trades,
        correlations: correlations,
        nonlinear_importance: nonlinear_importance,
        validation_reports: validation_reports,
        negative_analysis: negative_analysis,
        archetype_analysis: archetype_analysis,
        output_dir: output_dir
      )
    end
  end
end
