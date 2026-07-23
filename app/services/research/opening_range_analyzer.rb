# frozen_string_literal: true

module Research
  class OpeningRangeAnalyzer
    # Analyzes the day's NIFTY candles and returns a list of trade opportunities.
    # We support up to two opportunities per day: the first bullish breakout and/or the first bearish breakdown.
    # @param day_data [Hash] Daily data containing underlying_candles, prev_day_* info
    # @param range_minutes [Integer] Opening range duration (default 15)
    # @param target_points [Numeric] Target points for ORB continuation
    # @return [Array<Hash>] List of trade opportunity contexts
    def self.analyze(day_data, range_minutes: 15, target_points: 50.0)
      candles = day_data[:underlying_candles]
      return [] if candles.size < range_minutes

      date = day_data[:date]

      # 1. Split opening range and remaining session
      opening_candles = candles.first(range_minutes)
      remaining_candles = candles.drop(range_minutes)

      # 2. Compute opening range boundaries
      or_high = opening_candles.pluck(:high).max
      or_low = opening_candles.pluck(:low).min
      or_width = or_high - or_low

      # 3. Previous Day Context & Market Structure
      prev_close = day_data[:prev_day_close]
      prev_high = day_data[:prev_day_high]
      prev_low = day_data[:prev_day_low]
      today_open = candles.first[:open]

      gap_pct = 0.0
      if prev_close&.positive?
        gap_pct = ((today_open - prev_close) / prev_close) * 100.0
      end

      # Inside Day / Outside Day
      is_inside_day = false
      if prev_high && prev_low
        is_inside_day = today_open > prev_low && today_open < prev_high
      end
      is_outside_day = !is_inside_day

      relation_to_pdh_pdl = :inside
      if prev_high && today_open > prev_high
        relation_to_pdh_pdl = :above_pdh
      elsif prev_low && today_open < prev_low
        relation_to_pdh_pdl = :below_pdl
      end

      # Expiry proximity
      # NIFTY weekly options expire on Thursdays
      days_to_expiry = (4 - date.wday) % 7

      # 4. Find the first bullish breakout and first bearish breakdown
      breakouts = []
      bullish_triggered = false
      bearish_triggered = false

      remaining_candles.each_with_index do |c, idx|
        current_time = c[:timestamp]
        current_close = c[:close]
        overall_index = idx + range_minutes

        if !bullish_triggered && current_close > or_high
          bullish_triggered = true
          breakouts << {
            breakout_type: :bullish,
            entry_time: current_time,
            entry_price: current_close,
            entry_index: overall_index
          }
        elsif !bearish_triggered && current_close < or_low
          bearish_triggered = true
          breakouts << {
            breakout_type: :bearish,
            entry_time: current_time,
            entry_price: current_close,
            entry_index: overall_index
          }
        end
      end

      # 5. Build full context for each breakout
      breakouts.map do |brk|
        entry_idx = brk[:entry_index]
        post_entry = candles[entry_idx..]
        entry_price = brk[:entry_price]

        # Calculate max continuation / adverse excursion (MAE / MFE) on underlying
        max_continuation = 0.0
        max_adverse = 0.0
        sustained = false
        failed = false

        if brk[:breakout_type] == :bullish
          highest = post_entry.map { |c| c[:high] }.max || entry_price
          lowest = post_entry.map { |c| c[:low] }.min || entry_price
          max_continuation = highest - entry_price
          max_adverse = entry_price - lowest

          # Check if sustained
          hit_target = false
          post_entry.each do |c|
            if c[:high] >= entry_price + target_points
              hit_target = true
              break
            elsif c[:close] < or_high
              break
            end
          end
          sustained = hit_target
          failed = !sustained && post_entry.any? { |c| c[:close] < or_high }
        else # bearish
          highest = post_entry.map { |c| c[:high] }.max || entry_price
          lowest = post_entry.map { |c| c[:low] }.min || entry_price
          max_continuation = entry_price - lowest
          max_adverse = highest - entry_price

          # Check if sustained
          hit_target = false
          post_entry.each do |c|
            if c[:low] <= entry_price - target_points
              hit_target = true
              break
            elsif c[:close] > or_low
              break
            end
          end
          sustained = hit_target
          failed = !sustained && post_entry.any? { |c| c[:close] > or_low }
        end

        # Indicators at entry_time
        series = CandleSeries.new(symbol: "NIFTY", interval: "1")
        candles.first(entry_idx + 1).each do |c|
          series.add_candle(Candle.new(
            timestamp: c[:timestamp], open: c[:open], high: c[:high], low: c[:low], close: c[:close], volume: c[:volume]
          ))
        end

        atr = series.atr(14)
        adx = series.adx(14)
        rsi = series.rsi(14)
        vwap = series.current_vwap
        vwap_dist = vwap ? (entry_price - vwap) : 0.0

        # First candle features
        first_candle = opening_candles.first
        body_size = (first_candle[:close] - first_candle[:open]).abs
        total_size = first_candle[:high] - first_candle[:low]
        body_ratio = total_size.positive? ? (body_size / total_size) : 0.0

        {
          date: date,
          breakout_type: brk[:breakout_type],
          entry_time: brk[:entry_time],
          entry_index: entry_idx,
          underlying_entry_price: entry_price,
          or_high: or_high,
          or_low: or_low,
          or_width: or_width,
          gap_pct: gap_pct,
          is_inside_day: is_inside_day,
          is_outside_day: is_outside_day,
          relation_to_pdh_pdl: relation_to_pdh_pdl,
          days_to_expiry: days_to_expiry,
          day_of_week: date.strftime("%A"),
          max_continuation: max_continuation,
          max_adverse: max_adverse,
          sustained: sustained,
          failed: failed,
          atr: atr,
          adx: adx,
          rsi: rsi,
          vwap: vwap,
          vwap_dist: vwap_dist,
          first_candle_body_ratio: body_ratio,
          first_candle_volume: first_candle[:volume]
        }
      end
    end
  end
end
