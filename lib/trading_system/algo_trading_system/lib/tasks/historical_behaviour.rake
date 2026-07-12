# lib/tasks/historical_behaviour.rake
# frozen_string_literal: true

# INTRADAY OPTIONS BEHAVIOUR ANALYSIS
# Fetches historical ATM CE/PE data from DhanHQ for NIFTY/SENSEX expiry cycles.
# Produces insights to calibrate trailing stop & exit management systems.
#
# Usage:
#   rake 'options:historical_behaviour[8,NIFTY]'   # 8 weeks NIFTY
#   rake 'options:historical_behaviour[12]'        # 12 weeks both symbols
#   rake 'options:historical_behaviour[8,NIFTY,D]' # daily candles

namespace :options do
  desc "Intraday ATM options behaviour analysis — NIFTY/SENSEX, expiry-to-expiry"
  task :historical_behaviour, [:weeks, :symbol, :interval] do |_t, args|
    require 'date'
    require 'csv'
    require 'ostruct'
    require 'dotenv/load'
    require_relative '../../src/api/dhan_api_client'

    weeks    = (args[:weeks]  || 12).to_i
    symbols  = args[:symbol] ? [args[:symbol].upcase] : %w[NIFTY SENSEX]
    interval = args[:interval] || '5'

    SESSIONS = {
      'Morning'   => (9 * 60 + 15)..(11 * 60),
      'Midday'    => (11 * 60 + 1)..(13 * 60),
      'Afternoon' => (13 * 60 + 1)..(15 * 60 + 30)
    }.freeze

    DOW = %w[Sun Mon Tue Wed Thu Fri Sat].freeze

    # ── helpers ─────────────────────────────────────────────────────────────────

    # NIFTY = Thursday (4), SENSEX = Friday (5)
    def last_expiry_day(date, symbol)
      target_wday = symbol == 'SENSEX' ? 5 : 4
      diff = (date.wday - target_wday) % 7
      date - diff
    end

    def expiry_windows(weeks, symbol)
      today          = Date.today
      current_expiry = last_expiry_day(today, symbol)
      weeks.times.map do |i|
        expiry = current_expiry - (i * 7)
        { expiry: expiry, from: expiry - 6, to: expiry }
      end.reverse
    end

    def fmt_date(d)   = d.strftime('%Y-%m-%d')
    def pct(v, b)     = b.to_f.zero? ? 0.0 : ((v - b) / b.to_f * 100).round(2)

    def fetch_options(api_client, symbol, from_str, to_str, opt_type, interval)
      res = api_client.fetch_expired_options(
        underlying: symbol.downcase.to_sym,
        from_date: from_str,
        to_date: to_str,
        interval: interval,
        option_type: opt_type,
        strikes: ['ATM']
      )
      
      strike_key = "ATM_#{opt_type}"
      data = res[strike_key]
      return [] unless data && data[:timestamp]

      data[:timestamp].each_with_index.map do |ts, i|
        t = Time.at(ts).getlocal('+05:30')
        {
          time:    t,
          day:     t.wday,
          day_str: DOW[t.wday],
          mins:    t.hour * 60 + t.min,
          open:    data[:open][i].to_f,
          high:    data[:high][i].to_f,
          low:     data[:low][i].to_f,
          close:   data[:close][i].to_f,
          volume:  data[:volume][i].to_i,
          oi:      data[:oi][i].to_i,
          spot:    data[:spot][i].to_f,
          strike:  data[:strike] ? data[:strike][i].to_f : 0.0
        }
      end
    rescue => e
      puts "Error fetching #{symbol} #{opt_type}: #{e.message}"
      []
    end

    def cycle_stats(candles)
      return nil if candles.empty?

      entry   = candles.first[:open].to_f
      max_h   = candles.map { |c| c[:high] }.max.to_f
      min_l   = candles.map { |c| c[:low] }.min.to_f
      final_c = candles.last[:close].to_f
      vols    = candles.map { |c| c[:volume] }
      ois     = candles.map { |c| c[:oi] }
      spots   = candles.map { |c| c[:spot] }

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

    def day_breakdown(candles)
      candles.group_by { |c| c[:day_str] }.transform_values do |day_candles|
        day_open  = day_candles.first[:open].to_f
        day_close = day_candles.last[:close].to_f
        day_high  = day_candles.map { |c| c[:high] }.max.to_f
        day_low   = day_candles.map { |c| c[:low] }.min.to_f
        {
          open: day_open.round(2), high: day_high.round(2), low: day_low.round(2), close: day_close.round(2),
          high_pct: pct(day_high, day_open), low_pct: pct(day_low, day_open), oc_pct: pct(day_close, day_open)
        }
      end
    end

    def session_breakdown(candles)
      SESSIONS.transform_values do |range|
        sess = candles.select { |c| range.cover?(c[:mins]) }
        next nil if sess.empty?
        s_open = sess.first[:open].to_f
        {
          high_pct: pct(sess.map{|c| c[:high]}.max, s_open),
          low_pct: pct(sess.map{|c| c[:low]}.min, s_open),
          oc_pct: pct(sess.last[:close], s_open)
        }
      end
    end

    def spot_option_correlation(candles)
      base_spot = candles.first&.[](:spot).to_f
      base_opt = candles.first&.[](:open).to_f
      return nil if base_spot.zero? || base_opt.zero?
      pairs = candles.map { |c| [pct(c[:spot], base_spot), pct(c[:close], base_opt)] }
      n = pairs.size.to_f
      sx, sy, sx2, sxy = 0.0, 0.0, 0.0, 0.0
      pairs.each { |x, y| sx += x; sy += y; sx2 += x*x; sxy += x*y }
      denom = (n * sx2 - sx**2)
      return nil if denom.zero?
      slope = ((n * sxy - sx * sy) / denom).round(2)
      { slope: slope, note: "Option moves ~#{slope}x per 1% spot move" }
    end

    # ── print helpers ───────────────────────────────────────────────────────────
    G, R, Z, B, Y = "\e[32m", "\e[31m", "\e[0m", "\e[1m", "\e[33m"

    def print_cycle_stat(label, s)
      return printf("  %-4s  ⚠️  No data\n", label) unless s
      oc_f = s[:open_to_close_pct] >= 0 ? G : R
      printf "  %-4s  Strike:%-6.0f  Entry:%-8.2f  Exit:%-8.2f  #{oc_f}OC:%+.2f%%%s  #{G}MaxG:%+.2f%%%s  #{R}MaxL:%+.2f%%%s  #{Y}Retr:%+.2f%%%s  OIΔ:%+.2f%%  SpotΔ:%+.2f%%\n",
             label, s[:strike], s[:entry], s[:exit], s[:open_to_close_pct], Z, s[:max_gain_pct], Z, s[:max_loss_pct], Z, s[:post_peak_retrace], Z, s[:oi_change_pct], s[:spot_change_pct]
    end

    def aggregate_summary(all_stats)
      valid = all_stats.compact
      return nil if valid.empty?
      keys = %i[max_gain_pct max_loss_pct open_to_close_pct post_peak_retrace oi_change_pct spot_change_pct]
      { avg: keys.to_h { |k| [k, (valid.sum { |s| s[k].to_f } / valid.size).round(2)] }, n: valid.size }
    end

    # ── main ─────────────────────────────────────────────────────────────────────

    access_token = ENV['DHAN_ACCESS_TOKEN']
    if access_token.nil? || access_token.empty?
      begin
        puts "🔄 DHAN_ACCESS_TOKEN missing. Attempting to sync with provider..."
        require_relative '../../src/api/token_fetcher'
        Api::TokenFetcher.fetch_and_update_env
        access_token = ENV['DHAN_ACCESS_TOKEN']
      rescue => e
        puts "❌ Error: Could not fetch token: #{e.message}"
        puts "Please ensure AUTH_SERVER_BEARER_TOKEN is set or run 'bin/setup_auth' manually."
        next
      end
    end

    unless access_token
      puts "❌ Error: DHAN_ACCESS_TOKEN not set."
      next
    end
    api_client = Api::DhanApiClient.new(access_token: access_token)

    puts "\n#{'=' * 110}\n📊 INTRADAY OPTIONS BEHAVIOUR ANALYSIS\n#{'=' * 110}"
    csv_rows = []

    symbols.each do |symbol|
      puts "\n#{B}📈 #{symbol}#{Z}\n#{'═' * 110}"
      all_ce, all_pe = [], []
      windows = expiry_windows(weeks, symbol)

      windows.each do |w|
        from_s, to_s = fmt_date(w[:from]), fmt_date(w[:to])
        printf "\n#{B}🗓  Expiry: %s  Window: %s → %s#{Z}\n", w[:expiry].to_s, from_s, to_s
        
        ce_raw = fetch_options(api_client, symbol, from_s, to_s, 'CALL', interval)
        pe_raw = fetch_options(api_client, symbol, from_s, to_s, 'PUT',  interval)

        ce_s, pe_s = cycle_stats(ce_raw), cycle_stats(pe_raw)
        all_ce << ce_s; all_pe << pe_s
        print_cycle_stat("CE", ce_s); print_cycle_stat("PE", pe_s)

        ce_corr, pe_corr = spot_option_correlation(ce_raw), spot_option_correlation(pe_raw)
        puts "  #{Y}├─ CE Spot-to-Option: #{ce_corr[:note]}#{Z}" if ce_corr
        puts "  #{Y}├─ PE Spot-to-Option: #{pe_corr[:note]}#{Z}" if pe_corr

        csv_rows << { symbol: symbol, expiry: w[:expiry], from: from_s, to: to_s, ce: ce_s, pe: pe_s }
        sleep 0.1
      end

      ce_agg, pe_agg = aggregate_summary(all_ce), aggregate_summary(all_pe)
      if ce_agg
        puts "\n#{B}📊 #{symbol} Aggregate (n=#{ce_agg[:n]})#{Z}\n  #{B}CE Avg:#{Z} MaxG:#{G}%+.2f%%%s MaxL:#{R}%+.2f%%%s OC:%+.2f%% Retr:#{Y}%+.2f%%%s" % 
             [ce_agg[:avg][:max_gain_pct], Z, ce_agg[:avg][:max_loss_pct], Z, ce_agg[:avg][:open_to_close_pct], ce_agg[:avg][:post_peak_retrace], Z]
      end
    end
    
    puts "\n#{'=' * 110}\n✅ Done. Analysis complete.\n#{'=' * 110}"
  end
end
