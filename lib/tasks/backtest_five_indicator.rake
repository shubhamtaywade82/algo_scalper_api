# frozen_string_literal: true

namespace :backtest do
  namespace :five_indicator do
    desc 'Run five-indicator options buying backtest for NIFTY/SENSEX'
    task :run, %i[symbol days_back] => :environment do |_t, args|
      symbol    = (args[:symbol]    || ENV['SYMBOL']    || 'NIFTY').upcase
      days_back = (args[:days_back] || ENV['DAYS_BACK'] || '90').to_i

      $stdout.puts "\n#{'=' * 80}"
      $stdout.puts 'FIVE-INDICATOR OPTIONS BUYING BACKTEST'
      $stdout.puts '=' * 80
      $stdout.puts "Symbol:    #{symbol}"
      $stdout.puts "Days Back: #{days_back}"
      $stdout.puts '=' * 80

      result = Backtest::OptionsBuyingBacktester.call(
        symbol: symbol,
        days_back: days_back
      )

      result.print_summary
    end

    desc 'Run five-indicator backtest on all major indices'
    task :all, [:days_back] => :environment do |_t, args|
      days_back = (args[:days_back] || ENV['DAYS_BACK'] || '90').to_i
      indices = %w[NIFTY BANKNIFTY SENSEX FINNIFTY]

      all_results = {}

      indices.each do |symbol|
        $stdout.puts "\n#{'=' * 80}"
        $stdout.puts "BACKTESTING: #{symbol}"
        $stdout.puts '=' * 80

        begin
          result = Backtest::OptionsBuyingBacktester.call(
            symbol: symbol,
            days_back: days_back
          )
          all_results[symbol] = result.summary
          result.print_summary
        rescue StandardError => e
          $stdout.puts "❌ #{symbol} failed: #{e.class} - #{e.message}"
          $stdout.puts e.backtrace.first(3).join("\n  ")
          all_results[symbol] = { error: e.message }
        end
      end

      # Comparison table
      $stdout.puts "\n#{'=' * 80}"
      $stdout.puts 'COMPARISON SUMMARY'
      $stdout.puts '=' * 80
      $stdout.puts 'Index        Trades   Win Rate   Total P&L  Avg Win    Avg Loss'
      $stdout.puts '-' * 80

      all_results.each do |sym, s|
        next if s[:error]

        printf("%-12<sym>s %-8<total>d %-10<wr>.2f %-10<pnl>s %-10<aw>s %-10<al>s\n",
               sym: sym,
               total: s[:total_trades],
               wr: s[:win_rate],
               pnl: "₹#{s[:total_pnl]}",
               aw: "₹#{s[:avg_win]}",
               al: "₹#{s[:avg_loss]}")
      end
      $stdout.puts '=' * 80
    end

    desc 'Export five-indicator backtest trades to CSV'
    task :export, %i[symbol days_back output] => :environment do |_t, args|
      symbol     = (args[:symbol]    || ENV['SYMBOL']    || 'NIFTY').upcase
      days_back  = (args[:days_back] || ENV['DAYS_BACK'] || '90').to_i
      output     = args[:output] || "five_indicator_backtest_#{symbol}_#{Time.current.strftime('%Y%m%d_%H%M')}.csv"

      result = Backtest::OptionsBuyingBacktester.call(
        symbol: symbol,
        days_back: days_back
      )

      s = result.summary
      return $stdout.puts 'No trades to export' if s[:trades].empty?

      require 'csv'

      CSV.open(output, 'w') do |csv|
        csv << %w[Signal_Type Entry_Time Entry_Price Exit_Time Exit_Price PnL PnL_Pct Exit_Reason Minutes_Held
                  Entry_Index_Price HWM_Price HWM_Time Giveback_From_HWM_Pct Reason]

        s[:trades].each do |t|
          csv << [
            t[:signal_type].to_s.upcase,
            t[:entry_time],
            t[:entry_price],
            t[:exit_time],
            t[:exit_price],
            t[:pnl],
            t[:pnl_pct],
            t[:exit_reason],
            t[:minutes_held],
            t[:entry_index_price],
            t[:hwm_price],
            t[:hwm_time],
            t[:giveback_from_hwm_pct],
            t[:reason]
          ]
        end
      end

      $stdout.puts "✅ Exported #{s[:trades].size} trades to #{output}"
      result.print_summary
    end

    desc 'Grid-search exit parameters (stop/target/giveback/time-stop) across symbols'
    task :sweep, [:days_back] => :environment do |_t, args|
      days_back = (args[:days_back] || ENV['DAYS_BACK'] || '90').to_i
      symbols = %w[NIFTY BANKNIFTY SENSEX]

      # giveback_activation_pct: 999.0 and max_hold_minutes: 100_000 are sentinel "never fires"
      # values, so the no-giveback/no-time-stop baseline is one row in the same sweep and
      # directly comparable to every give-back variant, not a separate special case.
      grid = {
        stop_loss_pct: [0.35, 0.50, 0.65],
        target_pct: [1.50, 1.80, 2.20],
        giveback_activation_pct: [15.0, 30.0, 50.0, 999.0],
        giveback_pct: [0.10, 0.20],
        max_hold_minutes: [60, 120, 100_000]
      }

      $stdout.puts "Collecting entries for #{symbols.join(', ')} (#{days_back}d, one live fetch each)..."
      backtesters = symbols.index_with { |sym| Backtest::OptionsBuyingBacktester.for_sweep(symbol: sym, days_back: days_back) }
      backtesters.each { |sym, bt| $stdout.puts "  #{sym}: #{bt.raw_entries.size} entries collected" }

      combos = grid[:stop_loss_pct].product(grid[:target_pct], grid[:giveback_activation_pct], grid[:giveback_pct], grid[:max_hold_minutes])
      $stdout.puts "\nSweeping #{combos.size} parameter combos × #{symbols.size} symbols = #{combos.size * symbols.size} simulations (pure, no network)..."

      results = combos.map do |sl, tgt, ga, gp, mh|
        params = { stop_loss_pct: sl, target_pct: tgt, giveback_activation_pct: ga, giveback_pct: gp, max_hold_minutes: mh }
        per_symbol = symbols.index_with { |sym| backtesters[sym].resimulate(params).summary }

        total_pnl = per_symbol.values.sum { |s| s[:total_pnl] }
        total_trades = per_symbol.values.sum { |s| s[:total_trades] }
        wins = per_symbol.values.sum { |s| s[:winning_trades] }
        win_rate = total_trades.positive? ? (wins.to_f / total_trades * 100).round(2) : 0.0

        { params: params, total_pnl: total_pnl.round(2), total_trades: total_trades, win_rate: win_rate }
      end

      top = results.sort_by { |r| -r[:total_pnl] }.first(15)

      $stdout.puts "\n#{'=' * 100}"
      $stdout.puts 'TOP 15 PARAMETER COMBOS (ranked by combined total P&L across all symbols)'
      $stdout.puts '=' * 100
      $stdout.puts 'SL%    Target%  GiveAct%  Give%  MaxHold  Trades  WinRate  TotalP&L'
      $stdout.puts '-' * 100
      top.each do |r|
        p = r[:params]
        ga_label = p[:giveback_activation_pct] >= 999.0 ? 'off' : p[:giveback_activation_pct]
        mh_label = p[:max_hold_minutes] >= 100_000 ? 'off' : p[:max_hold_minutes]
        printf("%-7<sl>s%-9<tgt>s%-10<ga>s%-7<gp>s%-9<mh>s%-8<trades>d%-9<wr>.2f₹%<pnl>s\n",
               sl: p[:stop_loss_pct], tgt: p[:target_pct], ga: ga_label, gp: p[:giveback_pct], mh: mh_label,
               trades: r[:total_trades], wr: r[:win_rate], pnl: r[:total_pnl])
      end
      $stdout.puts '=' * 100

      baseline_params = { stop_loss_pct: 0.35, target_pct: 1.80, giveback_activation_pct: 999.0, giveback_pct: 0.10, max_hold_minutes: 100_000 }
      baseline_summary = symbols.map { |sym| backtesters[sym].resimulate(baseline_params).summary }
      baseline_pnl = baseline_summary.sum { |s| s[:total_pnl] }.round(2)
      baseline_trades = baseline_summary.sum { |s| s[:total_trades] }

      $stdout.puts "\nOriginal defaults, no giveback/time-stop (baseline): ₹#{baseline_pnl}, #{baseline_trades} trades"
      $stdout.puts "Best combo found: ₹#{top.first[:total_pnl]} (#{top.first[:params]})"
    end
  end
end
