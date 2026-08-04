# lib/tasks/historical_options.rake
# frozen_string_literal: true
#
# INTRADAY OPTIONS BEHAVIOUR ANALYSIS
# Fetches 5-min ATM CE/PE data from DhanHQ for NIFTY/SENSEX expiry cycles.
# Produces insights to calibrate trailing stop & exit management systems.
#
# Usage:
#   bundle exec rake 'options:historical_behaviour[8,NIFTY]'   # 8 weeks NIFTY
#   bundle exec rake 'options:historical_behaviour[12]'         # 12 weeks both symbols
#   bundle exec rake 'options:historical_behaviour[8,NIFTY,D]'  # daily candles

namespace :options do
  desc "Intraday ATM options behaviour analysis — NIFTY/SENSEX, expiry-to-expiry"
  task :historical_behaviour, [:weeks, :symbol, :interval] => :environment do |_t, args|
    weeks    = (args[:weeks]  || 12).to_i
    symbols  = args[:symbol].present? ? [args[:symbol].upcase] : %w[NIFTY SENSEX]
    interval = args[:interval] || '5'  # '5' = 5-min, '15' = 15-min, 'D' = daily

    SESSIONS = {
      'Morning'   => (9 * 60 + 15)..(11 * 60),           # 09:15 – 11:00
      'Midday'    => (11 * 60 + 1)..(13 * 60),            # 11:01 – 13:00
      'Afternoon' => (13 * 60 + 1)..(15 * 60 + 30)        # 13:01 – 15:30
    }.freeze

    DOW = %w[Sun Mon Tue Wed Thu Fri Sat].freeze

    puts "\n#{'=' * 110}"
    puts "📊 INTRADAY OPTIONS BEHAVIOUR ANALYSIS"
    puts "Symbols: #{symbols.join(', ')} | Lookback: #{weeks} weeks | Interval: #{interval}m | ATM Strike"
    puts "Purpose: Calibrate trailing stop & exit management based on real intraday options behaviour"
    puts "Generated: #{Time.current.strftime('%d-%b-%Y %H:%M %Z')}"
    puts '=' * 110

    # ── helpers ─────────────────────────────────────────────────────────────────

    def last_thursday(date)
      (date.wday - 4) % 7 == 0 ? date : date - ((date.wday - 4) % 7).days
    end

    def expiry_windows(weeks)
      today          = Time.zone.today
      current_expiry = last_thursday(today)
      weeks.times.map do |i|
        expiry = current_expiry - (i * 7).days
        { expiry: expiry, from: expiry - 6.days, to: expiry }
      end.reverse
    end

    def fmt_date(d)   = d.strftime('%Y-%m-%d')
    def pct(v, b)     = b.zero? ? 0.0 : ((v - b) / b.to_f * 100).round(2)
    def clr(v, positive_color = "\e[32m", negative_color = "\e[31m")
      v >= 0 ? "#{positive_color}%+.2f%%\e[0m" : "#{negative_color}%+.2f%%\e[0m"
    end

    def fetch_options(symbol, security_id, segment, from_str, to_str, opt_type, interval)
      raw = DhanHQ::Models::ExpiredOptionsData.fetch(
        exchange_segment: segment,
        interval:         interval,
        security_id:      security_id,
        instrument:       'OPTIDX',
        expiry_flag:      'WEEK',
        expiry_code:      1,
        strike:           'ATM',
        drv_option_type:  opt_type,
        required_data:    %w[open high low close volume oi spot strike],
        from_date:        from_str,
        to_date:          to_str
      )
      side = opt_type == 'CALL' ? 'ce' : 'pe'
      d    = raw&.data&.[](side)
      return [] unless d && d['timestamp']

      d['timestamp'].map.with_index do |ts, i|
        t = Time.at(ts).in_time_zone('Asia/Kolkata')
        {
          time:    t,
          day:     t.wday,
          day_str: DOW[t.wday],
          mins:    t.hour * 60 + t.min,
          open:    d['open'][i].to_f,
          high:    d['high'][i].to_f,
          low:     d['low'][i].to_f,
          close:   d['close'][i].to_f,
          volume:  d['volume'][i].to_i,
          oi:      d['oi'][i].to_i,
          spot:    d['spot'][i].to_f,
          strike:  d['strike'][i].to_f
        }
      end
    rescue StandardError => e
      Rails.logger.warn("[HistoricalOptions] #{symbol} #{opt_type}: #{e.message}")
      []
    end

    # ── per-expiry metrics ──────────────────────────────────────────────────────

    def cycle_stats(candles)
      return nil if candles.empty?

      entry   = candles.first[:open].to_f
      max_h   = candles.map { |c| c[:high] }.max.to_f
      min_l   = candles.map { |c| c[:low] }.min.to_f
      final_c = candles.last[:close].to_f
      vols    = candles.map { |c| c[:volume] }
      ois     = candles.map { |c| c[:oi] }
      spots   = candles.map { |c| c[:spot] }

      # pullback: after peak, what was the deepest low?
      peak_idx   = candles.index { |c| c[:high] == max_h }
      post_peak  = candles[(peak_idx || 0)..]
      pullback_l = post_peak.map { |c| c[:low] }.min.to_f
      retracement = pct(pullback_l, max_h)

      {
        entry:            entry.round(2),
        max_high:         max_h.round(2),
        max_low:          min_l.round(2),
        exit:             final_c.round(2),
        max_gain_pct:     pct(max_h,    entry),
        max_loss_pct:     pct(min_l,    entry),
        open_to_close_pct:pct(final_c,  entry),
        post_peak_retrace:retracement.round(2),
        avg_volume:       (vols.compact.sum / [vols.size, 1].max).round(0),
        oi_open:          ois.first.to_i,
        oi_close:         ois.last.to_i,
        oi_change_pct:    pct(ois.last.to_f, ois.first.to_f),
        spot_open:        spots.first.to_f.round(2),
        spot_close:       spots.last.to_f.round(2),
        spot_change_pct:  pct(spots.last.to_f, spots.first.to_f),
        strike:           candles.first[:strike].to_f.round(0),
        candle_count:     candles.size
      }
    end

    # ── per-day breakdown ───────────────────────────────────────────────────────

    def day_breakdown(candles)
      candles.group_by { |c| c[:day_str] }.transform_values do |day_candles|
        day_open  = day_candles.first[:open].to_f
        day_close = day_candles.last[:close].to_f
        day_high  = day_candles.map { |c| c[:high] }.max.to_f
        day_low   = day_candles.map { |c| c[:low] }.min.to_f
        {
          open:          day_open.round(2),
          high:          day_high.round(2),
          low:           day_low.round(2),
          close:         day_close.round(2),
          high_pct:      pct(day_high,  day_open),
          low_pct:       pct(day_low,   day_open),
          oc_pct:        pct(day_close, day_open),
          candles:       day_candles.size
        }
      end
    end

    # ── session breakdown ───────────────────────────────────────────────────────

    def session_breakdown(candles)
      SESSIONS.transform_values do |range|
        sess = candles.select { |c| range.cover?(c[:mins]) }
        next nil if sess.empty?

        s_open  = sess.first[:open].to_f
        s_close = sess.last[:close].to_f
        s_high  = sess.map { |c| c[:high] }.max.to_f
        s_low   = sess.map { |c| c[:low] }.min.to_f
        {
          open:    s_open.round(2),
          high:    s_high.round(2),
          low:     s_low.round(2),
          close:   s_close.round(2),
          high_pct:pct(s_high,  s_open),
          low_pct: pct(s_low,   s_open),
          oc_pct:  pct(s_close, s_open),
          candles: sess.size
        }
      end
    end

    # ── spot-to-option correlation ──────────────────────────────────────────────

    def spot_option_correlation(candles)
      # For each candle: compare spot % change vs option % change from window open
      base_spot   = candles.first[:spot].to_f
      base_option = candles.first[:open].to_f
      return nil if base_spot.zero? || base_option.zero?

      pairs = candles.map do |c|
        spot_chg   = pct(c[:spot].to_f, base_spot)
        option_chg = pct(c[:close].to_f, base_option)
        [spot_chg, option_chg]
      end

      # Simple linear regression: option_move = m * spot_move + b
      n  = pairs.size.to_f
      sx = pairs.sum { |x, _| x }
      sy = pairs.sum { |_, y| y }
      sx2= pairs.sum { |x, _| x ** 2 }
      sxy= pairs.sum { |x, y| x * y }
      denom = (n * sx2 - sx ** 2)
      return nil if denom.zero?

      slope = ((n * sxy - sx * sy) / denom).round(2)
      # slope ≈ how many % the option moves per 1% spot move
      { slope: slope, note: "Option moves ~#{slope}x per 1% spot move" }
    end

    # ── print helpers ───────────────────────────────────────────────────────────

    G = "\e[32m".freeze
    R = "\e[31m".freeze
    Z = "\e[0m".freeze
    B = "\e[1m".freeze
    Y = "\e[33m".freeze

    def clr_val(v)
      v >= 0 ? "#{G}%+.2f%%%#{Z}" : "#{R}%+.2f%%%#{Z}"
    end

    def print_cycle_stat(label, s)
      return printf("  %-4s  ⚠️  No data\n", label) unless s

      oc_fmt    = s[:open_to_close_pct] >= 0 ? G : R
      gain_fmt  = G
      loss_fmt  = R
      retrace_c = s[:post_peak_retrace].abs > 30 ? R : Y

      printf "  %-4s  Strike:%-6.0f  Entry:%-8.2f  Exit:%-8.2f  " \
             "#{oc_fmt}OC:%+.2f%%%s  " \
             "#{gain_fmt}MaxGain:%+.2f%%%s  " \
             "#{loss_fmt}MaxLoss:%+.2f%%%s  " \
             "#{retrace_c}Retrace:%+.2f%%%s  " \
             "OI Δ:%+.2f%%  SpotΔ:%+.2f%%\n",
             label, s[:strike], s[:entry], s[:exit],
             s[:open_to_close_pct], Z,
             s[:max_gain_pct], Z,
             s[:max_loss_pct], Z,
             s[:post_peak_retrace], Z,
             s[:oi_change_pct], s[:spot_change_pct]
    end

    def print_day_breakdown(days)
      order = %w[Mon Tue Wed Thu Fri]
      order.each do |d|
        next unless days[d]
        s = days[d]
        oc_c = s[:oc_pct] >= 0 ? G : R
        printf "      %-4s  Open:%-8.2f  H:%-8.2f  L:%-8.2f  C:%-8.2f  " \
               "#{G}Hi:%+.2f%%%s  #{R}Lo:%+.2f%%%s  #{oc_c}OC:%+.2f%%%s\n",
               d, s[:open], s[:high], s[:low], s[:close],
               s[:high_pct], Z, s[:low_pct], Z, s[:oc_pct], Z
      end
    end

    def print_sessions(sessions)
      sessions.each do |name, s|
        next unless s
        oc_c = s[:oc_pct] >= 0 ? G : R
        printf "      %-10s  #{G}Hi:%+.2f%%%s  #{R}Lo:%+.2f%%%s  #{oc_c}OC:%+.2f%%%s\n",
               name, s[:high_pct], Z, s[:low_pct], Z, s[:oc_pct], Z
      end
    end

    # ── aggregation across weeks ────────────────────────────────────────────────

    def aggregate_summary(all_stats)
      valid = all_stats.compact
      return nil if valid.empty?

      keys = %i[max_gain_pct max_loss_pct open_to_close_pct post_peak_retrace oi_change_pct spot_change_pct]
      avg  = keys.to_h { |k| [k, (valid.sum { |s| s[k].to_f } / valid.size).round(2)] }
      max  = keys.to_h { |k| [k, valid.map { |s| s[k].to_f }.max.round(2)] }
      min2 = keys.to_h { |k| [k, valid.map { |s| s[k].to_f }.min.round(2)] }

      { avg: avg, max: max, min: min2, n: valid.size }
    end

    # ── main ─────────────────────────────────────────────────────────────────────

    windows  = expiry_windows(weeks)
    csv_rows = []
    summaries = {}

    symbols.each do |symbol|
      security_id = Instrument.where(segment: 'I', symbol_name: symbol).first&.security_id
      segment     = symbol == 'SENSEX' ? 'BSE_FNO' : 'NSE_FNO'

      unless security_id
        puts "\n⚠️  #{symbol}: Could not find security_id — skipping"
        next
      end

      puts "\n#{'═' * 110}"
      puts "#{B}📈 #{symbol}#{Z}  (security_id: #{security_id}, segment: #{segment}, interval: #{interval}m)"
      puts '═' * 110

      all_ce_stats = []
      all_pe_stats = []

      windows.each do |w|
        from_str   = fmt_date(w[:from])
        to_str     = fmt_date(w[:to])
        expiry_str = w[:expiry].strftime('%d-%b-%Y (%a)')

        printf "\n#{B}🗓  Expiry: %-20s  Window: %s → %s#{Z}\n", expiry_str, from_str, to_str
        puts "  #{'-' * 100}"

        ce_raw = fetch_options(symbol, security_id, segment, from_str, to_str, 'CALL', interval)
        pe_raw = fetch_options(symbol, security_id, segment, from_str, to_str, 'PUT',  interval)

        ce_stat  = cycle_stats(ce_raw)
        pe_stat  = cycle_stats(pe_raw)
        ce_days  = day_breakdown(ce_raw)
        pe_days  = day_breakdown(pe_raw)
        ce_sess  = session_breakdown(ce_raw)
        pe_sess  = session_breakdown(pe_raw)
        ce_corr  = spot_option_correlation(ce_raw)
        pe_corr  = spot_option_correlation(pe_raw)

        all_ce_stats << ce_stat
        all_pe_stats << pe_stat

        # Cycle summary line
        puts "  #{B}── Cycle Summary#{Z}"
        print_cycle_stat("CE", ce_stat)
        print_cycle_stat("PE", pe_stat)

        if ce_stat && pe_stat
          spot_chg = ce_stat[:spot_change_pct]
          dir = spot_chg >= 0 ? "▲" : "▼"
          spot_c = spot_chg >= 0 ? G : R
          printf "  Spot: %-8.2f → %-8.2f (#{spot_c}%s%+.2f%%%s)\n",
                 ce_stat[:spot_open], ce_stat[:spot_close], dir, spot_chg, Z
        end

        # Correlation
        if ce_corr
          puts "  #{Y}├─ CE Spot-to-Option: #{ce_corr[:note]}#{Z}"
        end
        if pe_corr
          puts "  #{Y}├─ PE Spot-to-Option: #{pe_corr[:note]}#{Z}"
        end

        # Day-of-week breakdown
        if ce_days.any?
          puts "  #{B}── Day-of-Week (CE)#{Z}"
          print_day_breakdown(ce_days)
        end
        if pe_days.any?
          puts "  #{B}── Day-of-Week (PE)#{Z}"
          print_day_breakdown(pe_days)
        end

        # Session breakdown
        if ce_sess.any?
          puts "  #{B}── Intraday Sessions (CE)#{Z}"
          print_sessions(ce_sess)
        end
        if pe_sess.any?
          puts "  #{B}── Intraday Sessions (PE)#{Z}"
          print_sessions(pe_sess)
        end

        csv_rows << {
          symbol:           symbol,
          expiry:           w[:expiry].strftime('%Y-%m-%d'),
          from:             from_str,
          to:               to_str,
          ce:               ce_stat,
          pe:               pe_stat,
          ce_corr_slope:    ce_corr&.[](:slope),
          pe_corr_slope:    pe_corr&.[](:slope)
        }

        sleep 0.35
      end

      # ── Aggregate Stats across all expiry windows ─────────────────────────────
      ce_agg = aggregate_summary(all_ce_stats)
      pe_agg = aggregate_summary(all_pe_stats)

      puts "\n#{B}#{'═' * 110}#{Z}"
      puts "#{B}📊 #{symbol} — Aggregate Stats across #{weeks} weeks (n=#{ce_agg&.[](:n) || 0} cycles)#{Z}"
      puts '─' * 110

      if ce_agg
        puts "  #{B}CE Averages:#{Z}"
        printf "    MaxGain: #{G}%+.2f%%%s  MaxLoss: #{R}%+.2f%%%s  OC: %+.2f%%  " \
               "PostPeakRetrace: #{Y}%+.2f%%%s  OI Δ: %+.2f%%  SpotΔ: %+.2f%%\n",
               ce_agg[:avg][:max_gain_pct], Z, ce_agg[:avg][:max_loss_pct], Z,
               ce_agg[:avg][:open_to_close_pct],
               ce_agg[:avg][:post_peak_retrace], Z,
               ce_agg[:avg][:oi_change_pct], ce_agg[:avg][:spot_change_pct]

        printf "    Best week: MaxGain #{G}%+.2f%%%s | Worst week OC: #{R}%+.2f%%%s\n",
               ce_agg[:max][:max_gain_pct], Z, ce_agg[:min][:open_to_close_pct], Z
      end

      if pe_agg
        puts "  #{B}PE Averages:#{Z}"
        printf "    MaxGain: #{G}%+.2f%%%s  MaxLoss: #{R}%+.2f%%%s  OC: %+.2f%%  " \
               "PostPeakRetrace: #{Y}%+.2f%%%s  OI Δ: %+.2f%%  SpotΔ: %+.2f%%\n",
               pe_agg[:avg][:max_gain_pct], Z, pe_agg[:avg][:max_loss_pct], Z,
               pe_agg[:avg][:open_to_close_pct],
               pe_agg[:avg][:post_peak_retrace], Z,
               pe_agg[:avg][:oi_change_pct], pe_agg[:avg][:spot_change_pct]
      end

      puts "\n  #{B}🎯 Trailing Stop Calibration Insights:#{Z}"
      if ce_agg
        avg_gain    = ce_agg[:avg][:max_gain_pct]
        avg_retrace = ce_agg[:avg][:post_peak_retrace].abs
        suggested_trail = (avg_retrace * 0.8).round(1)
        breakeven_at    = (avg_gain * 0.25).round(1)
        puts "  CE ATM:"
        puts "    → Avg max gain:         #{G}#{avg_gain}%#{Z}"
        puts "    → Avg peak-retracement: #{Y}#{avg_retrace}%#{Z} after peak"
        puts "    → Suggested trail:      #{Y}#{suggested_trail}% from HWM#{Z} (80% of typical retrace)"
        puts "    → Breakeven trigger:    #{Y}#{breakeven_at}%#{Z} gain (25% of expected move)"
      end
      if pe_agg
        avg_gain    = pe_agg[:avg][:max_gain_pct]
        avg_retrace = pe_agg[:avg][:post_peak_retrace].abs
        suggested_trail = (avg_retrace * 0.8).round(1)
        breakeven_at    = (avg_gain * 0.25).round(1)
        puts "  PE ATM:"
        puts "    → Avg max gain:         #{G}#{avg_gain}%#{Z}"
        puts "    → Avg peak-retracement: #{Y}#{avg_retrace}%#{Z} after peak"
        puts "    → Suggested trail:      #{Y}#{suggested_trail}% from HWM#{Z}"
        puts "    → Breakeven trigger:    #{Y}#{breakeven_at}%#{Z} gain"
      end

      # ── AI Insights via Ollama ────────────────────────────────────────────────
      begin
        ai_client = Services::Ai::OllamaClient.instance
        if ai_client.enabled?
          puts "\n  #{B}🤖 AI Insights (Ollama — #{ai_client.selected_model})#{Z}"
          puts "  Analysing patterns to recommend trailing stop & exit strategy..."
          puts "  #{'-' * 100}"

          # Build a compact structured context from the aggregate data
          ce_summary_text = if ce_agg
            avg = ce_agg[:avg]
            "(CE) MaxGain avg: #{avg[:max_gain_pct]}%, MaxLoss avg: #{avg[:max_loss_pct]}%, " \
            "OC avg: #{avg[:open_to_close_pct]}%, Post-peak retrace avg: #{avg[:post_peak_retrace]}%, " \
            "OI change avg: #{avg[:oi_change_pct]}%, Spot change avg: #{avg[:spot_change_pct]}%"
          else
            "(CE) No data"
          end

          pe_summary_text = if pe_agg
            avg = pe_agg[:avg]
            "(PE) MaxGain avg: #{avg[:max_gain_pct]}%, MaxLoss avg: #{avg[:max_loss_pct]}%, " \
            "OC avg: #{avg[:open_to_close_pct]}%, Post-peak retrace avg: #{avg[:post_peak_retrace]}%, " \
            "OI change avg: #{avg[:oi_change_pct]}%, Spot change avg: #{avg[:spot_change_pct]}%"
          else
            "(PE) No data"
          end

          # Per-expiry cycle data for pattern context
          cycle_context = csv_rows.select { |r| r[:symbol] == symbol }.last(4).map do |r|
            ce = r[:ce]; pe = r[:pe]
            "Expiry #{r[:expiry]}: CE gain=#{ce&.[](:max_gain_pct)}% retrace=#{ce&.[](:post_peak_retrace)}% | " \
            "PE gain=#{pe&.[](:max_gain_pct)}% retrace=#{pe&.[](:post_peak_retrace)}% | spot=#{ce&.[](:spot_change_pct)}%"
          end.join("\n")

          prompt = <<~PROMPT
            You are an expert algorithmic options trader specialising in NSE/BSE index options (#{symbol}).
            You have been given #{weeks} weeks of historical ATM options behaviour data from DhanHQ (5-minute candles).

            ## Aggregate Statistics
            #{ce_summary_text}
            #{pe_summary_text}

            ## Recent Expiry Cycles
            #{cycle_context}

            ## Question
            Based on this real intraday ATM options data, please provide a concise expert analysis covering:

            1. **Trailing Stop Design**: What HWM trailing % is optimal for CE and PE given the post-peak retrace data? Should the system use different trailing distances intraday vs near expiry?

            2. **Session Observations**: When does the most significant premium move typically happen (Morning 09:15-11:00, Midday, Afternoon)? How should entry timing and stops adapt?

            3. **OI Signal Interpretation**: What does the OI change pattern (#{ce_agg&.dig(:avg, :oi_change_pct)}% CE, #{pe_agg&.dig(:avg, :oi_change_pct)}% PE) tell us about institutional positioning?

            4. **Exit Management Recommendation**: Given that options can give +#{ce_agg&.dig(:max, :max_gain_pct)}% peak gains but retrace sharply, what is the optimal 3-phase exit strategy (breakeven trigger → HWM trail → partial profit)?

            5. **Risk**: What are the key risks specific to #{symbol} ATM options intraday that the trailing system must account for?

            Be specific, use the numbers provided, and keep each section to 2-3 sentences.
          PROMPT

          ai_response = ai_client.chat(
            messages: [
              { role: 'system', content: 'You are an expert algorithmic options trader. Be concise and data-driven.' },
              { role: 'user',   content: prompt }
            ],
            temperature: 0.3
          )

          if ai_response.present?
            # Word-wrap the response to 100 chars
            ai_response.to_s.split("\n").each do |line|
              puts "  #{line}"
            end
          else
            puts "  ⚠️  AI response was empty (model may be loading, retry with OLLAMA_TIMEOUT=120)"
          end
        else
          puts "\n  ℹ️  AI insights skipped (Ollama not configured — set OLLAMA_BASE_URL to enable)"
        end
      rescue StandardError => e
        puts "\n  ⚠️  AI insights error: #{e.message}"
      end

      summaries[symbol] = { ce: ce_agg, pe: pe_agg }

    end

    # ── CSV ──────────────────────────────────────────────────────────────────────

    require 'csv'
    csv_path = "/tmp/options_intraday_#{symbols.join('_')}_#{Time.current.strftime('%Y%m%d_%H%M')}.csv"
    CSV.open(csv_path, 'w') do |csv|
      csv << %w[symbol expiry from to
                ce_entry ce_exit ce_max_gain_pct ce_max_loss_pct ce_oc_pct ce_retrace ce_oi_chg ce_spot_chg ce_corr_slope ce_strike
                pe_entry pe_exit pe_max_gain_pct pe_max_loss_pct pe_oc_pct pe_retrace pe_oi_chg pe_spot_chg pe_corr_slope pe_strike]
      csv_rows.each do |r|
        ce = r[:ce] || {}; pe = r[:pe] || {}
        csv << [r[:symbol], r[:expiry], r[:from], r[:to],
                ce[:entry], ce[:exit], ce[:max_gain_pct], ce[:max_loss_pct],
                ce[:open_to_close_pct], ce[:post_peak_retrace], ce[:oi_change_pct],
                ce[:spot_change_pct], r[:ce_corr_slope], ce[:strike],
                pe[:entry], pe[:exit], pe[:max_gain_pct], pe[:max_loss_pct],
                pe[:open_to_close_pct], pe[:post_peak_retrace], pe[:oi_change_pct],
                pe[:spot_change_pct], r[:pe_corr_slope], pe[:strike]]
      end
    end

    puts "\n#{'=' * 110}"
    puts "✅ Done. #{csv_rows.size} expiry cycles analysed."
    puts "📄 CSV: #{csv_path}"
    puts '=' * 110
  end
end
