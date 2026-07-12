# frozen_string_literal: true

require 'json'
require 'fileutils'
require 'date'
require_relative '../api/dhan_api_client'
require_relative 'options_engine'
require_relative '../strategies/trading_strategies'
require_relative '../utils/logger'

module Backtest
  # Main orchestrator for options backtesting
  class Orchestrator
    def initialize(access_token:, capital: 1_000_000, output_dir: './backtest_results')
      @access_token = access_token
      @capital = capital
      @output_dir = output_dir
      @logger = Utils::Logger
      @api_client = Api::DhanApiClient.new(access_token: @access_token)
      
      FileUtils.mkdir_p(@output_dir)
    end

    # Run complete backtest
    def run_backtest(config:)
      validate_config(config)

      @logger.info("system.backtest_init", 
        underlying: config[:underlying],
        strategy: config[:strategy],
        period: "#{config[:from_date]} to #{config[:to_date]}",
        capital: @capital
      )

      # 1. Fetch Spot Index Data (at strategy interval)
      @logger.info("system.fetching_spot_data", interval: config[:interval])
      spot_data = @api_client.fetch_intraday_history(
        security_id: map_underlying_id(config[:underlying]),
        exchange_segment: 'IDX_I',
        instrument: 'INDEX',
        interval: config[:interval].to_s,
        from_date: config[:from_date],
        to_date: config[:to_date]
      )
      spot_bars = convert_flat_to_bars(spot_data)
      @logger.info("system.spot_data_fetched", count: spot_bars.size)

      # 2. Fetch Option Data (at 1m interval)
      @logger.info("system.fetching_options_data", interval: '1')
      options_data = @api_client.fetch_expired_options(
        underlying: config[:underlying].to_sym,
        from_date: config[:from_date],
        to_date: config[:to_date],
        option_type: config[:option_type] || 'CALL',
        strikes: config[:strikes] || ['ATM', 'ATM+1', 'ATM-1'],
        interval: '1', # Always 1m for precise execution
        expiry_flag: config[:expiry_flag] || 'WEEK'
      )
      @logger.info("system.options_data_fetched", strike_count: options_data.keys.length)

      # 3. Backtest each strike
      all_backtest_results = {}

      options_data.each do |strike, data|
        option_bars = convert_flat_to_bars(data)
        @logger.info("system.simulating_strike", strike: strike, option_bars: option_bars.length)

        engine = OptionsBacktestEngine.new(capital: @capital, logger: @logger)
        strategy = TradingStrategies::StrategyFactory.create(config[:strategy], config[:strategy_params] || {})
        
        results = engine.backtest(
          symbol: strike,
          spot_bars: spot_bars,
          option_bars: option_bars,
          strategy: strategy,
          interval: config[:interval]
        )

        all_backtest_results[strike] = results
      end

      # 4. Aggregate and Report
      @logger.info("system.aggregating_results")
      aggregated = aggregate_results(all_backtest_results)
      generate_reports(aggregated, config)
      print_console_summary(aggregated, config)

      aggregated
    end

    private

    def print_console_summary(aggregated, config)
      require 'terminal-table'
      
      is_real_data = !@access_token.to_s.start_with?('MOCK')
      
      puts "\n" + "═" * 80
      puts "📊 BACKTEST SESSION SUMMARY"
      puts "═" * 80
      puts "  %-20s : %s" % ["Underlying Asset", config[:underlying].to_s.upcase]
      puts "  %-20s : %s" % ["Strategy Name", config[:strategy].to_s.upcase]
      puts "  %-20s : %s to %s" % ["Time Period", config[:from_date], config[:to_date]]
      puts "  %-20s : %s" % ["Interval", "#{config[:interval]} min (Spot) / 1 min (Option)"]
      puts "  %-20s : %s" % ["Option Type", config[:option_type] || 'CALL']
      puts "  %-20s : ₹#{@capital.round(0)}" % ["Starting Capital"]
      puts "  %-20s : %s" % ["Real Market Data", is_real_data ? "✅ YES" : "🧪 NO (Synthetic/Mock)"]
      puts "═" * 80
      
      rows = aggregated[:by_strike].map do |strike, res|
        s = res[:summary]
        [
          strike,
          s[:total_trades],
          s[:win_rate],
          s[:total_pnl],
          s[:max_drawdown],
          s[:sharpe_ratio]
        ]
      end
      
      # Add Total row
      total_wins = aggregated[:trades].count { |t| t[:status] == 'WIN' }
      total_trades = aggregated[:total_trades]
      win_rate = total_trades.positive? ? "#{(total_wins.to_f / total_trades * 100).round(2)}%" : "0%"
      
      rows << :separator
      rows << [
        'TOTAL AGGREGATE',
        total_trades,
        win_rate,
        "₹#{aggregated[:total_pnl]}",
        "-",
        "-"
      ]

      table = Terminal::Table.new do |t|
        t.headings = ['Strike', 'Trades', 'Win Rate', 'Net P&L', 'Max DD', 'Sharpe']
        t.rows = rows
        t.style = { border_i: 'x', border_y: '│', border_x: '─' }
      end

      puts table
      puts "═" * 80 + "\n"
    end

    # Validate configuration
    def validate_config(config)
      required_fields = %i[underlying strategy from_date to_date]
      required_fields.each do |field|
        raise ArgumentError, "Missing required field: #{field}" unless config[field]
      end
    end

    def map_underlying_id(symbol)
      { 'nifty' => 13, 'banknifty' => 12, 'finnifty' => 27, 'sensex' => 1 }.fetch(symbol.downcase)
    end

    def convert_flat_to_bars(data)
      return [] unless data[:timestamp] && data[:timestamp].any?
      
      data[:timestamp].each_with_index.map do |ts, i|
        {
          timestamp: ts.to_i,
          open: data[:open][i],
          high: data[:high][i],
          low: data[:low][i],
          close: data[:close][i],
          volume: data[:volume][i],
          iv: data[:iv] ? data[:iv][i] : 0.0,
          spot: data[:spot] ? data[:spot][i] : data[:close][i],
          strike: data[:strike] ? data[:strike][i] : 0.0
        }
      end.sort_by { |b| b[:timestamp] }
    end

    # Aggregate results across all strikes
    def aggregate_results(results_by_strike)
      all_trades = []
      total_pnl = 0.0
      total_trades = 0

      results_by_strike.each do |strike, result|
        all_trades.concat(result[:trades].map { |t| t.merge(strike: strike) })
        # Extract number from currency string "₹123.45"
        pnl_val = result[:summary][:total_pnl].to_s.gsub(/[^\d.-]/, '').to_f
        total_pnl += pnl_val
        total_trades += result[:summary][:total_trades]
      end

      {
        strikes_analyzed: results_by_strike.keys.length,
        total_trades: total_trades,
        total_pnl: total_pnl.round(2),
        trades: all_trades,
        by_strike: results_by_strike
      }
    end

    # Generate reports
    def generate_reports(aggregated, config)
      timestamp = Time.now.strftime('%Y%m%d_%H%M%S')
      
      # Summary report
      summary_file = File.join(@output_dir, "backtest_summary_#{timestamp}.json")
      File.write(summary_file, JSON.pretty_generate(format_summary_report(aggregated, config)))
      @logger.info("system.report_generated", path: summary_file)

      # Detailed trades report
      trades_file = File.join(@output_dir, "trades_#{timestamp}.json")
      File.write(trades_file, JSON.pretty_generate(aggregated[:trades]))
      @logger.info("system.report_generated", path: trades_file)

      # HTML dashboard
      html_file = File.join(@output_dir, "dashboard_#{timestamp}.html")
      File.write(html_file, generate_html_dashboard(aggregated, config, timestamp))
      @logger.info("system.report_generated", path: html_file)

      # CSV export for analysis
      csv_file = File.join(@output_dir, "trades_#{timestamp}.csv")
      File.write(csv_file, generate_csv_export(aggregated[:trades]))
      @logger.info("system.report_generated", path: csv_file)
    end

    # Format summary report
    def format_summary_report(aggregated, config)
      {
        metadata: {
          created_at: Time.now.iso8601,
          underlying: config[:underlying],
          strategy: config[:strategy],
          period: "#{config[:from_date]} to #{config[:to_date]}",
          capital: @capital
        },
        statistics: {
          strikes_analyzed: aggregated[:strikes_analyzed],
          total_trades: aggregated[:total_trades],
          total_pnl: "₹#{aggregated[:total_pnl].round(2)}",
          pnl_percentage: "#{((aggregated[:total_pnl] / @capital) * 100).round(2)}%",
          trades_by_strike: aggregated[:by_strike].each_with_object({}) do |(strike, result), acc|
            acc[strike] = {
              trades: result[:summary][:total_trades],
              win_rate: result[:summary][:win_rate],
              pnl: result[:summary][:total_pnl],
              pnl_pct: result[:summary][:total_pnl_pct]
            }
          end
        }
      }
    end

    # Generate HTML dashboard
    def generate_html_dashboard(aggregated, config, timestamp)
      trades_html = (aggregated[:trades] || []).map do |trade|
        pnl = (trade[:pnl] || 0.0).to_f
        pnl_pct = (trade[:pnl_pct] || 0.0).to_f
        
        <<~HTML
          <tr>
            <td>#{trade[:strike]}</td>
            <td>#{format_time(trade[:entry_time])}</td>
            <td>#{format_time(trade[:exit_time])}</td>
            <td>₹#{(trade[:entry_price] || 0.0).round(2)}</td>
            <td>₹#{(trade[:exit_price] || 0.0).round(2)}</td>
            <td>#{trade[:quantity]}</td>
            <td class="#{trade[:status] == 'WIN' ? 'win' : 'loss'}">₹#{pnl.round(2)}</td>
            <td>#{pnl_pct.round(2)}%</td>
          </tr>
        HTML
      end.join("\n")

      <<~HTML
        <!DOCTYPE html>
        <html>
        <head>
          <title>Options Backtest Report - #{timestamp}</title>
          <style>
            body { font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif; margin: 20px; background: #f5f5f5; color: #333; }
            .container { max-width: 1200px; margin: 0 auto; background: white; padding: 30px; border-radius: 12px; box-shadow: 0 4px 6px rgba(0,0,0,0.1); }
            h1 { color: #2c3e50; border-bottom: 3px solid #3498db; padding-bottom: 10px; margin-bottom: 20px; }
            .metrics { display: grid; grid-template-columns: repeat(4, 1fr); gap: 20px; margin: 25px 0; }
            .metric { background: #fff; padding: 20px; border: 1px solid #e0e0e0; border-left: 5px solid #3498db; border-radius: 8px; transition: transform 0.2s; }
            .metric:hover { transform: translateY(-2px); }
            .metric-label { font-size: 13px; color: #7f8c8d; text-transform: uppercase; letter-spacing: 1px; }
            .metric-value { font-size: 26px; font-weight: bold; color: #2c3e50; margin-top: 8px; }
            table { width: 100%; border-collapse: collapse; margin-top: 30px; }
            th { background: #3498db; color: white; padding: 15px; text-align: left; font-weight: 600; }
            td { padding: 12px 15px; border-bottom: 1px solid #ecf0f1; }
            tr:hover { background: #f9fbff; }
            .win { color: #27ae60; font-weight: bold; }
            .loss { color: #e74c3c; font-weight: bold; }
            .summary { background: #ebf5fb; padding: 20px; border-radius: 8px; margin-bottom: 30px; border: 1px solid #d6eaf8; line-height: 1.6; }
            .summary strong { color: #2980b9; }
          </style>
        </head>
        <body>
          <div class="container">
            <h1>📊 Options Backtest Report</h1>
            
            <div class="summary">
              <strong>Underlying:</strong> #{config[:underlying].to_s.upcase} |
              <strong>Strategy:</strong> #{config[:strategy].to_s.upcase} |
              <strong>Period:</strong> #{config[:from_date]} to #{config[:to_date]} |
              <strong>Capital:</strong> ₹#{@capital.round(0)}
            </div>

            <div class="metrics">
              <div class="metric">
                <div class="metric-label">Total Trades</div>
                <div class="metric-value">#{aggregated[:total_trades]}</div>
              </div>
              <div class="metric">
                <div class="metric-label">Total P&L</div>
                <div class="metric-value">₹#{aggregated[:total_pnl].round(2)}</div>
              </div>
              <div class="metric">
                <div class="metric-label">Return %</div>
                <div class="metric-value">#{((aggregated[:total_pnl] / @capital) * 100).round(2)}%</div>
              </div>
              <div class="metric">
                <div class="metric-label">Strikes</div>
                <div class="metric-value">#{aggregated[:strikes_analyzed]}</div>
              </div>
            </div>

            <h2>Trade Details</h2>
            <table>
              <thead>
                <tr>
                  <th>Strike</th>
                  <th>Entry Time</th>
                  <th>Exit Time</th>
                  <th>Entry Price</th>
                  <th>Exit Price</th>
                  <th>Quantity</th>
                  <th>P&L</th>
                  <th>Return %</th>
                </tr>
              </thead>
              <tbody>
                #{trades_html}
              </tbody>
            </table>
          </div>
        </body>
        </html>
      HTML
    end

    # Generate CSV export
    def generate_csv_export(trades)
      csv_lines = ["Strike,Entry Time,Exit Time,Entry Price,Exit Price,Quantity,PnL,Return %,Status"]
      
      trades.each do |trade|
        csv_lines << [
          trade[:strike],
          format_time(trade[:entry_time]),
          format_time(trade[:exit_time]),
          trade[:entry_price].round(2),
          trade[:exit_price].round(2),
          trade[:quantity],
          trade[:pnl].round(2),
          trade[:pnl_pct].round(2),
          trade[:status]
        ].join(',')
      end

      csv_lines.join("\n")
    end

    # Format unix timestamp
    def format_time(timestamp)
      Time.at(timestamp.to_i).strftime('%Y-%m-%d %H:%M:%S')
    end
  end
end
