# frozen_string_literal: true

# Analysis Accuracy Rake Task
#
# Parses AI/SMC analysis entries from development.log and evaluates them
# against actual OHLC price movement.
#
# Usage:
#   rake analysis:accuracy[NIFTY]
#   rake analysis:accuracy[BANKNIFTY]
#   rake analysis:accuracy[SENSEX]
#
# Environment Variables:
#   CANDLES_AFTER - Number of 5m candles to evaluate after analysis (default: 12)
#   LOG_FILE      - Path to log file (default: log/development.log)
#
# rubocop:disable Metrics/BlockLength, Lint/ConstantDefinitionInBlock, Metrics/ClassLength
# rubocop:disable Metrics/AbcSize, Metrics/MethodLength, Metrics/CyclomaticComplexity
# rubocop:disable Metrics/PerceivedComplexity, Style/FormatStringToken
namespace :analysis do
  desc 'Evaluate AI analysis accuracy against actual OHLC data'
  task :accuracy, [:symbol] => :environment do |_t, args|
    symbol = args[:symbol]&.upcase || 'NIFTY'
    candles_to_evaluate = ENV.fetch('CANDLES_AFTER', '12').to_i
    log_file = ENV.fetch('LOG_FILE', Rails.root.join('log/development.log').to_s)

    puts '=' * 80
    puts 'AI ANALYSIS ACCURACY REPORT'
    puts '=' * 80
    puts
    puts "Symbol: #{symbol}"
    puts "Log File: #{log_file}"
    puts "Evaluation Window: #{candles_to_evaluate} candles (5m) after each analysis"
    puts "Generated: #{Time.current.strftime('%Y-%m-%d %H:%M:%S %Z')}"
    puts

    unless File.exist?(log_file)
      puts "ERROR: Log file not found: #{log_file}"
      exit 1
    end

    # Step 1: Parse analysis entries from log
    parser = AnalysisLogParser.new(log_file, symbol)
    analyses = parser.parse

    if analyses.empty?
      puts "No AI analysis entries found for #{symbol} in #{log_file}"
      puts
      puts 'Expected log patterns:'
      puts "  - [SMCSanner] #{symbol}: <decision>"
      puts '  - Current price: ₹XXXXX'
      puts '  - BUY CE / BUY PE recommendations'
      exit 0
    end

    puts "Found #{analyses.size} analysis entries"
    puts

    # Step 2: Load instrument
    instrument = find_instrument(symbol)
    unless instrument
      puts "ERROR: Could not find instrument for #{symbol}"
      exit 1
    end

    # Step 3: Evaluate each analysis
    evaluator = AnalysisEvaluator.new(instrument, candles_to_evaluate)
    results = evaluator.evaluate_all(analyses)

    # Step 4: Generate report
    report = AccuracyReport.new(symbol, results)
    report.print_summary
    report.print_detailed_table
    report.print_verdicts

    puts
    puts '=' * 80
    puts 'Report Complete'
    puts '=' * 80
  end

  # ---------------------------------------------------------------------------
  # Helper: Find instrument by symbol
  # ---------------------------------------------------------------------------
  def find_instrument(symbol)
    # Try to find via index config
    indices = IndexConfigLoader.load_indices
    idx_cfg = indices.find { |i| (i[:key] || i['key']).to_s.upcase == symbol }

    if idx_cfg
      Instrument.find_by_sid_and_segment(
        security_id: idx_cfg[:sid].to_s,
        segment_code: idx_cfg[:segment]
      )
    else
      # Fallback: search by symbol name
      Instrument.where('symbol_name ILIKE ?', "%#{symbol}%").first
    end
  end

  # ===========================================================================
  # Log Parser: Extracts AI analysis entries from development.log
  # ===========================================================================
  class AnalysisLogParser
    # Patterns for extracting data
    PATTERNS = {
      # SMC decision line: [SMCSanner] NIFTY: call/put/no_trade
      decision: /\[SMCSanner\]\s+(\w+):\s+(call|put|no_trade)/i,

      # Current price in log
      current_price: /Current price:\s*₹?([\d,]+\.?\d*)/,

      # AI recommendation (BUY CE / BUY PE)
      recommendation: /(BUY\s+(?:CE|PE)|AVOID(?:\s+TRADING)?)/i,

      # Strike price
      strike: /Strike[:\s]+₹?([\d,]+)/i,

      # Entry premium
      entry_premium: /Entry[:\s]+(?:premium\s+)?₹?([\d,]+\.?\d*)/i,

      # SL premium
      sl_premium: /SL[:\s]+(?:premium\s+)?₹?([\d,]+\.?\d*)/i,

      # TP premium
      tp_premium: /TP[:\s]+(?:premium\s+)?₹?([\d,]+\.?\d*)/i,

      # Underlying SL
      sl_underlying: /SL\s+(?:underlying|level)[:\s]+₹?([\d,]+\.?\d*)/i,

      # Underlying TP
      tp_underlying: /TP\s+(?:underlying|level)[:\s]+₹?([\d,]+\.?\d*)/i,

      # Timestamp from log entry
      timestamp: /^\[?(\d{4}-\d{2}-\d{2}[T\s]\d{2}:\d{2}:\d{2})/,

      # Enqueued at timestamp
      enqueued_at: /"enqueued_at":"(\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2})/
    }.freeze

    def initialize(log_file, symbol)
      @log_file = log_file
      @symbol = symbol.upcase
    end

    def parse
      analyses = []
      current_analysis = nil
      current_line_no = 0

      File.foreach(@log_file) do |line|
        current_line_no += 1

        # Check for SMC decision for our symbol
        if line =~ /\[SMCSanner\]\s+#{@symbol}:\s+(call|put|no_trade)/i
          # Save previous analysis if exists
          analyses << current_analysis if current_analysis&.dig(:decision)

          # Start new analysis
          current_analysis = {
            line_number: current_line_no,
            symbol: @symbol,
            decision: Regexp.last_match(1).downcase.to_sym,
            timestamp: nil,
            price: nil,
            side: nil,
            strike: nil,
            entry_premium: nil,
            sl_premium: nil,
            tp_premium: nil,
            sl_underlying: nil,
            tp_underlying: nil
          }
        end

        # Extract data for current analysis (from surrounding lines)
        next unless current_analysis

        # Extract timestamp
        current_analysis[:timestamp] ||= parse_timestamp(Regexp.last_match(1)) if line =~ PATTERNS[:enqueued_at]

        # Extract price
        current_analysis[:price] ||= parse_number(Regexp.last_match(1)) if line =~ PATTERNS[:current_price]

        # Extract AI recommendation
        if line =~ PATTERNS[:recommendation]
          rec = Regexp.last_match(1).upcase
          current_analysis[:side] = case rec
                                    when /CE/ then :ce
                                    when /PE/ then :pe
                                    else :avoid
                                    end
        end

        # Extract strike
        current_analysis[:strike] ||= parse_number(Regexp.last_match(1)) if line =~ PATTERNS[:strike]

        # Extract entry premium
        if line =~ PATTERNS[:entry_premium]
          val = parse_number(Regexp.last_match(1))
          current_analysis[:entry_premium] ||= val if val < 1000 # Reasonable premium range
        end

        # Extract SL premium
        if line =~ PATTERNS[:sl_premium]
          val = parse_number(Regexp.last_match(1))
          current_analysis[:sl_premium] ||= val if val < 1000
        end

        # Extract TP premium
        if line =~ PATTERNS[:tp_premium]
          val = parse_number(Regexp.last_match(1))
          current_analysis[:tp_premium] ||= val if val < 1000
        end

        # Extract SL underlying
        current_analysis[:sl_underlying] ||= parse_number(Regexp.last_match(1)) if line =~ PATTERNS[:sl_underlying]

        # Extract TP underlying
        current_analysis[:tp_underlying] ||= parse_number(Regexp.last_match(1)) if line =~ PATTERNS[:tp_underlying]
      end

      # Add last analysis
      analyses << current_analysis if current_analysis&.dig(:decision)

      # Filter to only entries with sufficient data and infer side from decision
      analyses.select do |a|
        a[:side] ||= decision_to_side(a[:decision])
        a[:price].present?
      end
    end

    private

    def parse_number(str)
      str.to_s.delete(',').to_f
    end

    def parse_timestamp(str)
      Time.zone.parse(str)
    rescue StandardError
      nil
    end

    def decision_to_side(decision)
      case decision
      when :call then :ce
      when :put then :pe
      else :avoid
      end
    end
  end

  # ===========================================================================
  # Evaluator: Compares analysis predictions with actual OHLC data
  # ===========================================================================
  class AnalysisEvaluator
    def initialize(instrument, candle_count)
      @instrument = instrument
      @candle_count = candle_count
      @ohlc_cache = {}
    end

    def evaluate_all(analyses)
      analyses.map.with_index { |analysis, idx| evaluate_single(analysis, idx + 1) }
    end

    def evaluate_single(analysis, index)
      result = analysis.dup
      result[:index] = index

      # Get OHLC data after the analysis timestamp
      candles = fetch_candles_after(analysis[:timestamp], analysis[:price])

      if candles.empty?
        result[:outcome] = :no_data
        result[:direction_correct] = nil
        result[:mfe] = nil
        result[:mae] = nil
        return result
      end

      entry_price = analysis[:price]
      side = analysis[:side]

      # Calculate Max Favorable Excursion (MFE) and Max Adverse Excursion (MAE)
      if side == :ce
        # BUY CE: favorable = price goes UP, adverse = price goes DOWN
        result[:mfe] = candles.pluck(:high).max - entry_price
        result[:mae] = entry_price - candles.pluck(:low).min
        result[:direction_correct] = candles.any? { |c| c[:high] > entry_price }
      elsif side == :pe
        # BUY PE: favorable = price goes DOWN, adverse = price goes UP
        result[:mfe] = entry_price - candles.pluck(:low).min
        result[:mae] = candles.pluck(:high).max - entry_price
        result[:direction_correct] = candles.any? { |c| c[:low] < entry_price }
      else
        # AVOID - no direction to evaluate
        result[:mfe] = 0
        result[:mae] = 0
        result[:direction_correct] = nil
      end

      # Determine outcome based on SL/TP levels
      result[:outcome] = determine_outcome(analysis, candles, side)

      result
    end

    private

    def fetch_candles_after(timestamp, _entry_price)
      # If no timestamp, try to find candles around the entry price
      # This is a fallback for when timestamp parsing fails
      return fetch_recent_candles if timestamp.nil?

      date = timestamp.to_date
      cache_key = date.to_s

      @ohlc_cache[cache_key] ||= begin
        raw_data = @instrument.intraday_ohlc(
          interval: '5',
          from_date: date.to_s,
          to_date: (date + 2.days).to_s,
          days: 3
        )

        parse_raw_ohlc(raw_data)
      rescue StandardError => e
        Rails.logger.warn("[AnalysisAccuracy] Failed to fetch OHLC: #{e.message}")
        []
      end

      # Filter to candles after the analysis timestamp
      candles = @ohlc_cache[cache_key].select { |c| c[:timestamp] && c[:timestamp] > timestamp }
      candles.first(@candle_count)
    end

    def fetch_recent_candles
      return @recent_candles if defined?(@recent_candles)

      raw_data = @instrument.intraday_ohlc(
        interval: '5',
        days: 5
      )

      @recent_candles = parse_raw_ohlc(raw_data).last(@candle_count * 3)
    rescue StandardError => e
      Rails.logger.warn("[AnalysisAccuracy] Failed to fetch recent OHLC: #{e.message}")
      @recent_candles = []
    end

    def parse_raw_ohlc(raw_data)
      return [] unless raw_data.is_a?(Hash)

      timestamps = raw_data['timestamp'] || raw_data[:timestamp] || []
      opens = raw_data['open'] || raw_data[:open] || []
      highs = raw_data['high'] || raw_data[:high] || []
      lows = raw_data['low'] || raw_data[:low] || []
      closes = raw_data['close'] || raw_data[:close] || []

      timestamps.each_with_index.filter_map do |ts, i|
        {
          timestamp: parse_timestamp(ts),
          open: opens[i].to_f,
          high: highs[i].to_f,
          low: lows[i].to_f,
          close: closes[i].to_f
        }
      end
    end

    def parse_timestamp(timestamp_value)
      case timestamp_value
      when Time, DateTime, ActiveSupport::TimeWithZone then timestamp_value
      when String then Time.zone.parse(timestamp_value)
      when Integer then Time.zone.at(timestamp_value)
      end
    rescue StandardError
      nil
    end

    def determine_outcome(analysis, candles, side)
      return :no_trade if side == :avoid

      sl = analysis[:sl_underlying]
      tp = analysis[:tp_underlying]

      # If no SL/TP levels, just check direction
      return :unknown unless sl && tp

      candles.each do |candle|
        if side == :ce
          # CE: TP is above entry, SL is below entry
          return :failure if candle[:low] <= sl
          return :success if candle[:high] >= tp
        else
          # PE: TP is below entry, SL is above entry
          return :failure if candle[:high] >= sl
          return :success if candle[:low] <= tp
        end
      end

      :no_move
    end
  end

  # ===========================================================================
  # Report Generator: Formats and prints the accuracy report
  # ===========================================================================
  class AccuracyReport
    def initialize(symbol, results)
      @symbol = symbol
      @results = results
    end

    def print_summary
      puts '-' * 80
      puts 'SUMMARY'
      puts '-' * 80
      puts

      total = @results.size
      tradable = @results.reject { |r| r[:side] == :avoid }
      ce_trades = @results.select { |r| r[:side] == :ce }
      pe_trades = @results.select { |r| r[:side] == :pe }
      avoid_trades = @results.select { |r| r[:side] == :avoid }

      # Direction accuracy
      direction_evaluable = tradable.reject { |r| r[:direction_correct].nil? }
      direction_correct = direction_evaluable.count { |r| r[:direction_correct] }
      direction_accuracy = direction_evaluable.any? ? (direction_correct.to_f / direction_evaluable.size * 100) : 0

      # Outcomes
      successes = tradable.count { |r| r[:outcome] == :success }
      failures = tradable.count { |r| r[:outcome] == :failure }
      no_moves = tradable.count { |r| r[:outcome] == :no_move }
      unknown = tradable.count { |r| r[:outcome] == :unknown }

      success_rate = tradable.any? ? (successes.to_f / tradable.size * 100) : 0
      failure_rate = tradable.any? ? (failures.to_f / tradable.size * 100) : 0
      no_move_rate = tradable.any? ? (no_moves.to_f / tradable.size * 100) : 0

      puts format('%-30s %s', 'Total Analyses:', total)
      puts format('%-30s %s', 'Tradable Signals (CE/PE):', tradable.size)
      puts format('%-30s %s', '  - BUY CE:', ce_trades.size)
      puts format('%-30s %s', '  - BUY PE:', pe_trades.size)
      puts format('%-30s %s', 'AVOID Signals:', avoid_trades.size)
      puts
      puts format('%-30s %.1f%% (%d/%d)', 'Direction Accuracy:', direction_accuracy, direction_correct,
                  direction_evaluable.size)
      puts
      puts format('%-30s %.1f%% (%d)', 'Success Rate (TP hit):', success_rate, successes)
      puts format('%-30s %.1f%% (%d)', 'Failure Rate (SL hit):', failure_rate, failures)
      puts format('%-30s %.1f%% (%d)', 'No Move Rate:', no_move_rate, no_moves)
      puts format('%-30s %d', 'Unknown (no SL/TP data):', unknown)
      puts
    end

    def print_detailed_table
      puts '-' * 80
      puts 'DETAILED RESULTS'
      puts '-' * 80
      puts

      header = '#    Timestamp    Side   Entry      Direction  Outcome    MFE      MAE     '
      puts header
      puts '-' * 80

      @results.each do |r|
        timestamp = r[:timestamp]&.strftime('%m-%d %H:%M') || 'N/A'
        side = r[:side].to_s.upcase
        entry = r[:price] ? format('₹%.1f', r[:price]) : 'N/A'
        direction = case r[:direction_correct]
                    when true then '✓ CORRECT'
                    when false then '✗ WRONG'
                    else 'N/A'
                    end
        outcome = r[:outcome].to_s.upcase
        mfe = r[:mfe] ? format('%.1f', r[:mfe]) : 'N/A'
        mae = r[:mae] ? format('%.1f', r[:mae]) : 'N/A'

        puts format(
          '%-4d %-12s %-6s %-10s %-10s %-10s %-8s %-8s',
          r[:index], timestamp, side, entry, direction, outcome, mfe, mae
        )
      end
      puts
    end

    def print_verdicts
      puts '-' * 80
      puts 'DATA-DERIVED VERDICTS'
      puts '-' * 80
      puts

      tradable = @results.reject { |r| r[:side] == :avoid }
      ce_trades = @results.select { |r| r[:side] == :ce }
      pe_trades = @results.select { |r| r[:side] == :pe }

      # Verdict 1: Directional Bias
      ce_correct = ce_trades.count { |r| r[:direction_correct] == true }
      pe_correct = pe_trades.count { |r| r[:direction_correct] == true }
      ce_wrong = ce_trades.count { |r| r[:direction_correct] == false }
      pe_wrong = pe_trades.count { |r| r[:direction_correct] == false }

      puts '1. DIRECTIONAL BIAS ANALYSIS:'
      if ce_trades.any? && pe_trades.any?
        ce_accuracy = ce_trades.any? ? (ce_correct.to_f / ce_trades.size * 100) : 0
        pe_accuracy = pe_trades.any? ? (pe_correct.to_f / pe_trades.size * 100) : 0

        puts format('   CE Accuracy: %.1f%% (%d correct, %d wrong)', ce_accuracy, ce_correct, ce_wrong)
        puts format('   PE Accuracy: %.1f%% (%d correct, %d wrong)', pe_accuracy, pe_correct, pe_wrong)

        if ce_accuracy < 40 && pe_accuracy > 60
          puts '   ⚠️  VERDICT: AI has BULLISH bias in BEARISH market (recommending CE when PE needed)'
        elsif pe_accuracy < 40 && ce_accuracy > 60
          puts '   ⚠️  VERDICT: AI has BEARISH bias in BULLISH market (recommending PE when CE needed)'
        elsif ce_accuracy < 50 && pe_accuracy < 50
          puts '   ⚠️  VERDICT: AI has poor direction detection in both directions'
        else
          puts '   ✓  VERDICT: No significant directional bias detected'
        end
      elsif ce_trades.any?
        ce_accuracy = ce_correct.to_f / ce_trades.size * 100
        puts format('   Only CE trades found: %.1f%% accuracy (%d/%d)', ce_accuracy, ce_correct, ce_trades.size)
        puts '   ⚠️  VERDICT: AI recommending CE in predominantly BEARISH market' if ce_accuracy < 50
      elsif pe_trades.any?
        pe_accuracy = pe_correct.to_f / pe_trades.size * 100
        puts format('   Only PE trades found: %.1f%% accuracy (%d/%d)', pe_accuracy, pe_correct, pe_trades.size)
        puts '   ⚠️  VERDICT: AI recommending PE in predominantly BULLISH market' if pe_accuracy < 50
      else
        puts '   No tradable signals found'
      end
      puts

      # Verdict 2: Overtrading
      avoid_count = @results.count { |r| r[:side] == :avoid }
      trade_count = tradable.size
      failure_count = tradable.count { |r| r[:outcome] == :failure }

      puts '2. OVERTRADING ANALYSIS:'
      puts format('   Trade signals: %d, Avoid signals: %d', trade_count, avoid_count)

      if trade_count.positive? && avoid_count.zero?
        failure_rate = failure_count.to_f / trade_count * 100
        if failure_rate > 60
          puts "   ⚠️  VERDICT: AI is OVERTRADING (no AVOID signals, #{format('%.0f', failure_rate)}% failure rate)"
        else
          puts '   ✓  VERDICT: Trade frequency appears appropriate'
        end
      elsif trade_count > avoid_count * 3 && failure_count > trade_count / 2
        puts '   ⚠️  VERDICT: AI may be OVERTRADING (high trade count with high failures)'
      else
        puts '   ✓  VERDICT: Trade/Avoid ratio appears balanced'
      end
      puts

      # Verdict 3: Fighting HTF Trend
      puts '3. HIGHER TIMEFRAME TREND ALIGNMENT:'

      if tradable.empty?
        puts '   No tradable signals to evaluate'
      else
        # Calculate overall market direction from MFE/MAE
        total_mfe_up = ce_trades.sum { |r| r[:mfe] || 0 }
        total_mfe_down = pe_trades.sum { |r| r[:mfe] || 0 }
        total_mae_up = ce_trades.sum { |r| r[:mae] || 0 }
        total_mae_down = pe_trades.sum { |r| r[:mae] || 0 }

        net_ce = total_mfe_up - total_mae_up
        net_pe = total_mfe_down - total_mae_down

        puts format('   CE trades net movement: %.1f points (MFE: %.1f, MAE: %.1f)', net_ce, total_mfe_up, total_mae_up)
        puts format('   PE trades net movement: %.1f points (MFE: %.1f, MAE: %.1f)', net_pe, total_mfe_down,
                    total_mae_down)

        if ce_trades.size > pe_trades.size && net_ce.negative? && net_pe.positive?
          puts '   ⚠️  VERDICT: AI is FIGHTING BEARISH HTF trend (more CE trades but PE more profitable)'
        elsif pe_trades.size > ce_trades.size && net_pe.negative? && net_ce.positive?
          puts '   ⚠️  VERDICT: AI is FIGHTING BULLISH HTF trend (more PE trades but CE more profitable)'
        elsif ce_wrong > ce_correct * 2 || pe_wrong > pe_correct * 2
          puts '   ⚠️  VERDICT: AI direction predictions consistently wrong - likely fighting HTF trend'
        else
          puts '   ✓  VERDICT: AI appears aligned with higher timeframe trend'
        end
      end
      puts
    end
  end
end
# rubocop:enable Metrics/BlockLength, Lint/ConstantDefinitionInBlock, Metrics/ClassLength
# rubocop:enable Metrics/AbcSize, Metrics/MethodLength, Metrics/CyclomaticComplexity
# rubocop:enable Metrics/PerceivedComplexity, Style/FormatStringToken
