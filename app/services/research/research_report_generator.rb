# frozen_string_literal: true

require "csv"
require "json"
require "fileutils"

module Research
  class ResearchReportGenerator
    # Generates final CSV, JSON, and Console reports from trade-based opportunities.
    # @param trades [Array<Hash>] List of trade opportunity hashes
    # @param correlations [Hash] Feature correlations with MFE
    # @param nonlinear_importance [Hash] Mutual Information gains and binned probabilities
    # @param validation_reports [Hash] Bootstrapped CIs and IS/OOS validations
    # @param negative_analysis [Hash] Frequencies of failed breakout reasons
    # @param archetype_analysis [Hash] Frequencies of auction archetypes
    # @param output_dir [String] Directory path to save files
    # @return [Hash] Compiled aggregate metrics
    def self.run(trades, correlations: {}, nonlinear_importance: {}, validation_reports: {}, negative_analysis: {}, archetype_analysis: {}, output_dir: "data/research")
      return {} if trades.empty?

      FileUtils.mkdir_p(output_dir)

      total_trades = trades.size
      bull_trades = trades.count { |t| t[:breakout_type] == :bullish }
      bear_trades = trades.count { |t| t[:breakout_type] == :bearish }

      # 1. Advanced Exit Strategy Performance (specifically for ATM option)
      exit_stats = evaluate_exits(trades, strike_label: "ATM")

      # 2. Strike Performance Comparison
      strike_stats = compare_strikes(trades)

      # 3. Conditional Probabilities
      probabilities = compute_probabilities(trades)

      # 4. Run Hypothesis Validation Engine
      hypotheses = Research::HypothesisEngine.run(trades)

      # Compile aggregate payload
      aggregate = {
        total_trade_opportunities: total_trades,
        breakout_type_split: {
          bullish: bull_trades,
          bearish: bear_trades
        },
        exit_performance_atm: exit_stats,
        strike_comparison: strike_stats,
        conditional_probabilities: probabilities,
        hypotheses: hypotheses.map do |h|
          {
            description: h.description,
            sample_size: h.sample_size,
            success_rate: h.success_rate.round(2),
            expectancy_r: h.expectancy.round(2),
            verdict: h.verdict
          }
        end,
        feature_importance: correlations,
        nonlinear_importance: nonlinear_importance,
        statistical_validation: validation_reports,
        negative_research: negative_analysis,
        archetype_distribution: archetype_analysis,
        trades: trades
      }

      # 5. Save JSON and CSVs
      write_json(aggregate, trades, output_dir)
      write_opportunities_csv(trades, output_dir)
      write_strike_comparison_csv(trades, output_dir)

      # Print gorgeous console report
      print_console_summary(aggregate)

      aggregate
    end

    private

    def self.average(arr)
      return 0.0 if arr.empty?
      arr.sum.to_f / arr.size
    end

    def self.median(arr)
      return 0.0 if arr.empty?
      sorted = arr.sort
      len = sorted.length
      (sorted[(len - 1) / 2] + sorted[len / 2]) / 2.0
    end

    def self.std_dev(arr)
      return 0.0 if arr.size <= 1
      avg = average(arr)
      variance = arr.map { |x| (x - avg)**2 }.sum / (arr.size - 1)
      Math.sqrt(variance)
    end

    def self.evaluate_exits(trades, strike_label:)
      exit_names = Research::ExitCaptureAnalyzer::STRATEGY_NAMES

      exit_names.index_with do |name|
        returns = trades.map { |t| t[:strikes][strike_label][:exits][name][:return_pct] }
        efficiencies = trades.map { |t| t[:strikes][strike_label][:exits][name][:capture_efficiency] }
        times = trades.map { |t| t[:strikes][strike_label][:exits][name][:holding_time_minutes] }
        retentions = trades.map { |t| t[:strikes][strike_label][:exits][name][:opportunity_retention_ratio] || 0.0 }
        lost_profit = trades.map { |t| t[:strikes][strike_label][:exits][name][:lost_profit_points] || 0.0 }
        
        wins = returns.select { |r| r > 0.0 }
        losses = returns.select { |r| r < 0.0 }
        win_rate = returns.size > 0 ? (wins.size.to_f / returns.size) * 100.0 : 0.0

        # Expectancy
        expectancy = average(returns)

        # Standard Deviation
        sd = std_dev(returns)

        # Sharpe (simplified trade-level Sharpe)
        sharpe = sd > 0 ? (expectancy / sd) : 0.0

        # Sortino
        downside_variance = losses.map { |r| r**2 }.sum / [returns.size, 1].max
        downside_sd = Math.sqrt(downside_variance)
        sortino = downside_sd > 0 ? (expectancy / downside_sd) : 0.0

        # Profit Factor
        gross_wins = wins.sum
        gross_losses = losses.sum.abs
        profit_factor = gross_losses > 0 ? (gross_wins / gross_losses) : (gross_wins > 0 ? 99.9 : 1.0)

        edge_score = Research::EdgeScorer.score(returns, 30.0)

        {
          win_rate_pct: win_rate.round(2),
          avg_return_pct: expectancy.round(2),
          median_return_pct: median(returns).round(2),
          std_dev_pct: sd.round(2),
          sharpe_ratio: sharpe.round(3),
          sortino_ratio: sortino.round(3),
          profit_factor: profit_factor.round(2),
          expectancy_pct: expectancy.round(2),
          avg_capture_efficiency: average(efficiencies).round(4),
          avg_opportunity_retention: average(retentions).round(4),
          avg_lost_profit_points: average(lost_profit).round(2),
          avg_holding_time_mins: average(times).round(1),
          edge_score: edge_score
        }
      end
    end

    def self.compare_strikes(trades)
      strikes = ["ATM-2", "ATM-1", "ATM", "ATM+1", "ATM+2"]
      
      strikes.index_with do |strike|
        mfe_vals = trades.map { |t| t[:strikes][strike][:mfe_pct] }
        mae_vals = trades.map { |t| t[:strikes][strike][:mae_pct] }
        decay_vals = trades.map { |t| t[:strikes][strike][:drawdown_from_peak_pct] }
        elasticity_vals = trades.map { |t| t[:strikes][strike][:trade_elasticity] }

        # ROI under hybrid divergence exit (our best strategy)
        hybrid_returns = trades.map { |t| t[:strikes][strike][:exits][:hybrid_divergence][:return_pct] }
        wins = hybrid_returns.count { |r| r > 0.0 }

        {
          avg_mfe_pct: average(mfe_vals).round(2),
          avg_mae_pct: average(mae_vals).round(2),
          avg_decay_from_peak_pct: average(decay_vals).round(2),
          avg_elasticity: average(elasticity_vals).round(3),
          hybrid_exit_avg_return_pct: average(hybrid_returns).round(2),
          hybrid_exit_win_rate_pct: ((wins.to_f / trades.size) * 100.0).round(2)
        }
      end
    end

    def self.compute_probabilities(trades)
      avg_opening_vol = average(trades.map { |t| t[:first_candle_volume] || 0.0 })
      
      # 1. P(CE > 50% MFE | gap up, strong volume, bullish breakout)
      bull_filters = trades.select do |t|
        t[:gap_pct] > 0.15 &&
        (t[:first_candle_volume] || 0) >= avg_opening_vol &&
        t[:breakout_type] == :bullish
      end
      num_ce_gt_50 = bull_filters.count { |t| t[:strikes]["ATM"][:mfe_pct] >= 50.0 }
      p_ce_expansion = bull_filters.any? ? (num_ce_gt_50.to_f / bull_filters.size) * 100.0 : 0.0

      # 2. P(PE > 50% MFE | gap down, below VWAP, bearish breakdown)
      bear_filters = trades.select do |t|
        t[:gap_pct] < -0.15 &&
        t[:vwap_dist] < 0 &&
        t[:breakout_type] == :bearish
      end
      num_pe_gt_50 = bear_filters.count { |t| t[:strikes]["ATM"][:mfe_pct] >= 50.0 }
      p_pe_expansion = bear_filters.any? ? (num_pe_gt_50.to_f / bear_filters.size) * 100.0 : 0.0

      # 3. P(decay > 25% after peak | strong MFE >= 50%)
      strong_mfe_trades = trades.select { |t| t[:strikes]["ATM"][:mfe_pct] >= 50.0 }
      decay_gt_25 = strong_mfe_trades.count { |t| t[:strikes]["ATM"][:drawdown_from_peak_pct] >= 25.0 }
      p_decay = strong_mfe_trades.any? ? (decay_gt_25.to_f / strong_mfe_trades.size) * 100.0 : 0.0

      {
        p_atm_ce_mfe_above_50_given_bull_filters: p_ce_expansion.round(2),
        p_atm_pe_mfe_above_50_given_bear_filters: p_pe_expansion.round(2),
        p_decay_above_25_given_strong_mfe: p_decay.round(2)
      }
    end

    def self.write_json(aggregate, trades, output_dir)
      payload = {
        generated_at: Time.current.to_s,
        summary: aggregate,
        trades: trades.map do |t|
          {
            date: t[:date].to_s,
            event_type: t[:event_type],
            breakout_type: t[:breakout_type],
            entry_time: t[:entry_time].to_s,
            underlying_entry_price: t[:underlying_entry_price],
            or_high: t[:or_high],
            or_low: t[:or_low],
            or_width: t[:or_width],
            gap_pct: t[:gap_pct],
            is_inside_day: t[:is_inside_day],
            is_outside_day: t[:is_outside_day],
            relation_to_pdh_pdl: t[:relation_to_pdh_pdl],
            days_to_expiry: t[:days_to_expiry],
            day_of_week: t[:day_of_week],
            max_continuation: t[:max_continuation],
            max_adverse: t[:max_adverse],
            sustained: t[:sustained],
            failed: t[:failed],
            archetype: t[:archetype],
            atr: t[:atr],
            adx: t[:adx],
            rsi: t[:rsi],
            vwap: t[:vwap],
            vwap_dist: t[:vwap_dist],
            first_candle_body_ratio: t[:first_candle_body_ratio],
            first_candle_volume: t[:first_candle_volume],
            expected_opportunity_score: t[:expected_opportunity_score],
            strikes: t[:strikes],
            regime: t[:regime],
            lifecycle_phases: t[:lifecycle_phases],
            failure_reason: t[:failure_reason]
          }
        end
      }
      File.write(File.join(output_dir, "research_report_v4.json"), JSON.pretty_generate(payload))
    end

    def self.write_opportunities_csv(trades, output_dir)
      csv_path = File.join(output_dir, "trade_opportunities.csv")
      CSV.open(csv_path, "wb") do |csv|
        csv << [
          "Date", "Breakout Type", "Entry Time", "Underlying Entry Price", "OR High", "OR Low", "OR Width",
          "Gap %", "Inside Day", "Outside Day", "Relation PDH/PDL", "Days To Expiry", "Day Of Week",
          "Max Continuation", "Max Adverse", "Sustained", "Failed", "ATR", "ADX", "RSI", "VWAP Dist",
          "ATM MFE %", "ATM MAE %", "ATM Peak Time", "ATM Time To Peak Min", "ATM Decay %",
          "ATM Gamma Eff", "ATM Expansion Quality Score", "ATM Peak Exhaustion Score",
          "ATM Expected Opportunity Score",
          "ATM Time To 50%", "ATM Time Above 50%",
          "ATM Exit Hybrid Return %", "ATM Exit Hybrid Capture Eff", "ATM Exit Hybrid Retention Ratio", "ATM Exit Hybrid Lost Profit",
          "Volatility Regime", "Trend Regime", "Auction Archetype", "Failure Reason"
        ]
        
        trades.each do |t|
          atm = t[:strikes]["ATM"]
          hybrid = atm[:exits][:hybrid_divergence]
          csv << [
            t[:date],
            t[:breakout_type],
            t[:entry_time],
            t[:underlying_entry_price],
            t[:or_high],
            t[:or_low],
            t[:or_width],
            t[:gap_pct],
            t[:is_inside_day],
            t[:is_outside_day],
            t[:relation_to_pdh_pdl],
            t[:days_to_expiry],
            t[:day_of_week],
            t[:max_continuation],
            t[:max_adverse],
            t[:sustained],
            t[:failed],
            t[:atr],
            t[:adx],
            t[:rsi],
            t[:vwap_dist],
            atm[:mfe_pct],
            atm[:mae_pct],
            atm[:peak_time],
            atm[:time_to_peak_minutes],
            atm[:drawdown_from_peak_pct],
            atm[:gamma_efficiency],
            atm[:expansion_quality_score],
            atm[:exhaustion][:peak_exhaustion_score],
            t[:expected_opportunity_score],
            atm[:thresholds][:time_to_50],
            atm[:thresholds][:time_above_50],
            hybrid[:return_pct],
            hybrid[:capture_efficiency],
            hybrid[:opportunity_retention_ratio],
            hybrid[:lost_profit_points],
            t[:regime]&.[](:volatility),
            t[:regime]&.[](:trend),
            t[:archetype],
            t[:failure_reason]
          ]
        end
      end
    end

    def self.write_strike_comparison_csv(trades, output_dir)
      csv_path = File.join(output_dir, "strike_comparison_report.csv")
      CSV.open(csv_path, "wb") do |csv|
        csv << [
          "Date", "Breakout Type", "Strike Label", "Entry Price", "Peak Price", "MFE %", "MAE %",
          "Time To Peak Min", "Decay %", "Elasticity", "Gamma Eff", "Expansion Quality Score",
          "Peak Exhaustion Score", "Expected Opportunity Score", "Time To 50%", "Time Above 50%",
          "Hybrid Return %", "Hybrid Capture Eff", "Hybrid Retention Ratio", "Hybrid Lost Profit",
          "Trail 20 Return %", "Trail 20 Capture Eff",
          "Momentum Return %", "Momentum Capture Eff",
          "Volatility Regime", "Trend Regime", "Auction Archetype"
        ]
        
        trades.each do |t|
          ["ATM-2", "ATM-1", "ATM", "ATM+1", "ATM+2"].each do |strike_label|
            str = t[:strikes][strike_label]
            hybrid = str[:exits][:hybrid_divergence]
            trail = str[:exits][:trail_20]
            mom = str[:exits][:momentum_decay]
            csv << [
              t[:date],
              t[:breakout_type],
              strike_label,
              str[:entry_price],
              str[:peak_price],
              str[:mfe_pct],
              str[:mae_pct],
              str[:time_to_peak_minutes],
              str[:drawdown_from_peak_pct],
              str[:trade_elasticity],
              str[:gamma_efficiency],
              str[:expansion_quality_score],
              str[:exhaustion][:peak_exhaustion_score],
              t[:expected_opportunity_score],
              str[:thresholds][:time_to_50],
              str[:thresholds][:time_above_50],
              hybrid[:return_pct],
              hybrid[:capture_efficiency],
              hybrid[:opportunity_retention_ratio] || 0.0,
              hybrid[:lost_profit_points] || 0.0,
              trail[:return_pct],
              trail[:capture_efficiency],
              mom[:return_pct],
              mom[:capture_efficiency],
              t[:regime]&.[](:volatility),
              t[:regime]&.[](:trend),
              t[:archetype]
            ]
          end
        end
      end
    end

    def self.print_console_summary(agg)
      puts "\n" + "=" * 120
      puts "📊 INSTITUTIONAL OPENING AUCTION RESEARCH OPERATING SYSTEM (V7)"
      puts "=" * 120
      puts "Total Simulated Trade Events: #{agg[:total_trade_opportunities]}"
      puts "  Bullish Breakouts: #{agg[:breakout_type_split][:bullish]} | Bearish Breakdowns: #{agg[:breakout_type_split][:bearish]}"

      puts "\n🏫 AUCTION ARCHETYPE DISTRIBUTION MATRIX:"
      agg[:archetype_distribution].each do |arch, count|
        bar = ("█" * count).ljust(15)
        printf("  - %-25s : %2d events (%5.1f%%) | %s\n", 
               arch.to_s.titleize, count, (count.to_f / agg[:total_trade_opportunities]) * 100.0, bar)
      end

      if agg[:nonlinear_importance].any?
        puts "\n🧠 SHANNON INFORMATION GAIN MATRIX (Non-linear Mutual Info to MFE >= 30%):"
        agg[:nonlinear_importance][:information_gains].each do |feat, gain|
          bar = ("█" * (gain * 20).round).ljust(20)
          printf("  %-25s : %6.4f bits | %s\n", feat.to_s.titleize, gain, bar)
        end

        puts "\n🎲 BINNED CONDITIONAL PROBABILITY MATRIX: P(ATM Option Expansion >= 30% | Bin)"
        agg[:nonlinear_importance][:conditional_probability_tables].each do |feat_name, bin_table|
          puts "  #{feat_name.to_s.titleize}:"
          bin_table.each do |bin_name, stats|
            printf("    * %-20s : Win Rate %5.1f%% (sample size: %d)\n", 
                   bin_name.to_s.titleize, stats[:probability_pct], stats[:sample])
          end
        end
      end

      puts "\n🧠 LINEAR FEATURE CORRELATION MATRIX (MFE Strength):"
      agg[:feature_importance].each do |feature, r|
        bar = ("█" * (r.abs * 20).round).ljust(20)
        printf("  %-25s : %6.4f | %s\n", feature.to_s.titleize, r, bar)
      end

      puts "\n⚠️ NEGATIVE RESEARCH: failed breakout reason distribution:"
      agg[:negative_research].each do |reason, count|
        printf("  - %-25s : %d trades (%5.1f%%)\n", 
               reason.to_s.titleize, count, (count.to_f / [agg[:negative_research].values.sum, 1].max) * 100.0)
      end

      puts "\n🧪 HYPOTHESIS VALIDATION MATRIX:"
      printf("  %-50s | %6s | %7s | %10s | %10s\n", 
             "Hypothesis Rule", "Sample", "Success", "Expectancy", "Verdict")
      puts "  " + "-" * 92
      
      agg[:hypotheses].each do |h|
        printf("  %-50s | %6d | %6.1f%% | %8.2fR | %10s\n",
               h[:description].truncate(50), h[:sample_size], h[:success_rate], h[:expectancy_r], h[:verdict].to_s.upcase)
      end

      puts "\n🛡️ EXIT STRATEGY MATRIX & WALK-FORWARD STATISTICAL VALIDATION (ATM STRIKE):"
      printf("  %-18s | %8s | %8s | %6s | %8s | %8s | %10s | %10s | %10s\n", 
             "Strategy", "Win Rate", "Avg Ret", "Sharpe", "Retent R", "Lost Pts", "95% Ret CI", "IS / OOS Ret", "Edge Score")
      puts "  " + "-" * 115
      
      sorted_exits = agg[:exit_performance_atm].sort_by { |_, stats| -stats[:avg_return_pct] }
      sorted_exits.each do |name, stats|
        val = agg[:statistical_validation][name]
        ci = val ? val[:bootstrap][:expected_return_95_ci] : [0.0, 0.0]
        splits = val ? val[:split_validation] : { is_avg_return_pct: 0.0, oos_avg_return_pct: 0.0 }

        printf("  %-18s | %7.2f%% | %7.2f%% | %6.3f | %8.2f | %8.1f | [%5.1f, %4.1f] | %5.1f%% / %4.1f%% | %10d\n",
               name.to_s.titleize, 
               stats[:win_rate_pct], 
               stats[:avg_return_pct], 
               stats[:sharpe_ratio], 
               stats[:avg_opportunity_retention],
               stats[:avg_lost_profit_points],
               ci[0], ci[1],
               splits[:is_avg_return_pct], splits[:oos_avg_return_pct],
               stats[:edge_score] || 0)
      end

      puts "\n🎯 STRIKE COMPARISON (ATM-2 to ATM+2) UNDER HYBRID EXIT:"
      printf("  %-12s | %8s | %8s | %7s | %10s | %9s | %8s\n", 
             "Strike", "Avg MFE", "Avg MAE", "Decay", "Elasticity", "Avg Return", "Win Rate")
      puts "  " + "-" * 76
      
      ["ATM-2", "ATM-1", "ATM", "ATM+1", "ATM+2"].each do |strike|
        stats = agg[:strike_comparison][strike]
        printf("  %-12s | %7.2f%% | %7.2f%% | %6.2f%% | %10.3f | %8.2f%% | %7.2f%%\n",
               strike, 
               stats[:avg_mfe_pct], 
               stats[:avg_mae_pct], 
               stats[:avg_decay_from_peak_pct], 
               stats[:avg_elasticity], 
               stats[:hybrid_exit_avg_return_pct],
               stats[:hybrid_exit_win_rate_pct])
      end

      puts "\n🎲 CONDITIONAL PROBABILITIES & PATTERN MINING:"
      puts "  P(ATM CE MFE > 50% | Bull filters)       : #{agg[:conditional_probabilities][:p_atm_ce_mfe_above_50_given_bull_filters]}%"
      puts "  P(ATM PE MFE > 50% | Bear filters)       : #{agg[:conditional_probabilities][:p_atm_pe_mfe_above_50_given_bear_filters]}%"
      puts "  P(Premium decay > 25% after peak | MFE>=50%): #{agg[:conditional_probabilities][:p_decay_above_25_given_strong_mfe]}%"
      puts "=" * 110 + "\n"
    end
  end
end
