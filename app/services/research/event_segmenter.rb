# frozen_string_literal: true

module Research
  class EventSegmenter
    # Scans a day's candles and segments them into distinct opening auction events.
    # Allows a single day to yield multiple separate events (e.g. initial breakout and subsequent reversal).
    # @param day_data [Hash] Daily candles and preceding day metrics
    # @param target_points [Numeric] Target points for ORB continuation
    # @return [Array<Hash>] List of segmented events
    def self.segment(day_data, target_points: 50.0)
      candles = day_data[:underlying_candles] || []
      return [] if candles.size < 30

      events = []

      # 1. Identify primary Opening Range boundaries (first 15m)
      first_15m = candles.first(15)
      or_high = first_15m.pluck(:high).max
      or_low = first_15m.pluck(:low).min
      or_width = or_high - or_low

      # Track active state to avoid overlapping event entry signals
      primary_breakout_triggered = false
      reversal_triggered = false

      # Classify day archetype for context
      archetype = Research::AuctionArchetypeClassifier.classify(day_data)

      # 2. Iterate post-15m candles
      candles.each_with_index do |c, idx|
        next if idx < 15

        # Event A: Primary Opening Range Breakout / Breakdown
        if !primary_breakout_triggered
          event_type = nil
          if c[:close] > or_high
            event_type = :bullish_breakout
          elsif c[:close] < or_low
            event_type = :bearish_breakdown
          end

          if event_type
            primary_breakout_triggered = true

            # Aligned to the open of the next minute candle
            entry_idx = [idx + 1, candles.size - 1].min
            entry_candle = candles[entry_idx]

            # Measure post-entry path to classify if it succeeded or failed
            post_entry = candles[entry_idx..]
            max_cont = 0.0
            max_adv = 0.0

            if event_type == :bullish_breakout
              highest = post_entry.map { |x| x[:high] }.max || entry_candle[:open]
              lowest = post_entry.map { |x| x[:low] }.min || entry_candle[:open]
              max_cont = highest - entry_candle[:open]
              max_adv = entry_candle[:open] - lowest
            else
              lowest = post_entry.map { |x| x[:low] }.min || entry_candle[:open]
              highest = post_entry.map { |x| x[:high] }.max || entry_candle[:open]
              max_cont = entry_candle[:open] - lowest
              max_adv = highest - entry_candle[:open]
            end

            sustained = max_cont >= target_points
            failed = !sustained

            events << {
              date: day_data[:date],
              event_id: "#{day_data[:date]}_primary_#{event_type}",
              event_type: failed ? :failed_breakout : event_type,
              breakout_type: event_type == :bullish_breakout ? :bullish : :bearish,
              entry_time: entry_candle[:timestamp],
              entry_index: entry_idx,
              underlying_entry_price: entry_candle[:open],
              or_high: or_high,
              or_low: or_low,
              or_width: or_width,
              max_continuation: max_cont,
              max_adverse: max_adv,
              sustained: sustained,
              failed: failed,
              archetype: archetype,
              atr: day_data[:atr],
              adx: day_data[:adx],
              rsi: day_data[:rsi],
              vwap: day_data[:vwap],
              vwap_dist: day_data[:vwap_dist],
              gap_pct: day_data[:gap_pct] || 0.0,
              is_inside_day: day_data[:is_inside_day] || false,
              is_outside_day: day_data[:is_outside_day] || false,
              relation_to_pdh_pdl: day_data[:relation_to_pdh_pdl] || :inside,
              days_to_expiry: day_data[:days_to_expiry] || 4,
              day_of_week: day_data[:date].strftime("%A"),
              first_candle_body_ratio: day_data[:first_candle_body_ratio] || 0.5,
              first_candle_volume: day_data[:first_candle_volume] || 0
            }
          end

        # Event B: Secondary afternoon reversal event (occurs after 12:00 IST / index 165)
        elsif !reversal_triggered && idx >= 165
          # A reversal is defined by crossing back across the opening range boundaries in the opposite direction
          first_event = events.first
          next unless first_event

          is_reversal = false
          rev_type = nil

          if first_event[:breakout_type] == :bullish && c[:close] < or_low
            is_reversal = true
            rev_type = :bearish_reversal
          elsif first_event[:breakout_type] == :bearish && c[:close] > or_high
            is_reversal = true
            rev_type = :bullish_reversal
          end

          if is_reversal
            reversal_triggered = true

            entry_idx = [idx + 1, candles.size - 1].min
            entry_candle = candles[entry_idx]

            post_entry = candles[entry_idx..]
            max_cont = 0.0
            max_adv = 0.0

            if rev_type == :bullish_reversal
              highest = post_entry.map { |x| x[:high] }.max || entry_candle[:open]
              lowest = post_entry.map { |x| x[:low] }.min || entry_candle[:open]
              max_cont = highest - entry_candle[:open]
              max_adv = entry_candle[:open] - lowest
            else
              lowest = post_entry.map { |x| x[:low] }.min || entry_candle[:open]
              highest = post_entry.map { |x| x[:high] }.max || entry_candle[:open]
              max_cont = entry_candle[:open] - lowest
              max_adv = highest - entry_candle[:open]
            end

            events << {
              date: day_data[:date],
              event_id: "#{day_data[:date]}_reversal_#{rev_type}",
              event_type: :reversal,
              breakout_type: rev_type == :bullish_reversal ? :bullish : :bearish,
              entry_time: entry_candle[:timestamp],
              entry_index: entry_idx,
              underlying_entry_price: entry_candle[:open],
              or_high: or_high,
              or_low: or_low,
              or_width: or_width,
              max_continuation: max_cont,
              max_adverse: max_adv,
              sustained: max_cont >= target_points,
              failed: max_cont < target_points,
              archetype: archetype,
              atr: day_data[:atr],
              adx: day_data[:adx],
              rsi: day_data[:rsi],
              vwap: day_data[:vwap],
              vwap_dist: day_data[:vwap_dist],
              gap_pct: day_data[:gap_pct] || 0.0,
              is_inside_day: day_data[:is_inside_day] || false,
              is_outside_day: day_data[:is_outside_day] || false,
              relation_to_pdh_pdl: day_data[:relation_to_pdh_pdl] || :inside,
              days_to_expiry: day_data[:days_to_expiry] || 4,
              day_of_week: day_data[:date].strftime("%A"),
              first_candle_body_ratio: day_data[:first_candle_body_ratio] || 0.5,
              first_candle_volume: day_data[:first_candle_volume] || 0
            }
          end
        end
      end

      events.each_with_index do |ev, idx|
        ev[:event_uuid] = "#{ev[:date].strftime('%Y%m%d')}-#{idx + 1}"
      end

      events
    end
  end
end
