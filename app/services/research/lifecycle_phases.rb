# frozen_string_literal: true

module Research
  class LifecyclePhases
    # Traces the 7 option lifecycle phases for a trade opportunity.
    # @param option_candles [Array<Hash>] Option candles
    # @param underlying_candles [Array<Hash>] NIFTY candles
    # @param trade_opp [Hash] The breakout context
    # @param expansion_ctx [Hash] Option expansion metrics
    # @return [Hash] Lifecycle phase timelines and durations
    def self.trace(option_candles, underlying_candles, trade_opp, expansion_ctx)
      start_of_day = option_candles.first[:timestamp]
      entry_time = trade_opp[:entry_time]
      peak_time = expansion_ctx[:peak_time]
      end_of_day = option_candles.last[:timestamp]

      # 1. Compression Phase: Pre-open to market open
      comp_start = start_of_day
      comp_end = start_of_day # standard start

      # 2. Auction Phase: Market open (09:15) to breakout entry
      auction_start = start_of_day
      auction_end = entry_time
      auction_duration = ((auction_end - auction_start) / 60).round

      # 3. Ignition Phase: Breakout entry (3 minutes)
      ignition_start = entry_time
      ignition_end = [entry_time + 3.minutes, end_of_day].min
      ignition_duration = ((ignition_end - ignition_start) / 60).round

      # 4. Expansion Phase: Ignition end to Peak price
      expansion_start = ignition_end
      expansion_end = [peak_time, expansion_start].max
      expansion_duration = ((expansion_end - expansion_start) / 60).round

      # 5. Momentum Decay Phase: Peak price to when velocity turns negative/reverses
      mom_decay_start = expansion_end
      mom_decay_end = mom_decay_start

      # Find when the close price breaks below the low of the last 2 candles
      opt_idx = option_candles.index { |c| c[:timestamp] >= mom_decay_start } || 0
      option_candles[opt_idx..].each_with_index do |c, offset|
        idx = opt_idx + offset
        next if offset < 2
        prev_low = [option_candles[idx - 1][:low], option_candles[idx - 2][:low]].min
        if c[:close] < prev_low
          mom_decay_end = c[:timestamp]
          break
        end
      end
      mom_decay_duration = ((mom_decay_end - mom_decay_start) / 60).round

      # 6. Exhaustion Phase: End of momentum decay to when PES is maximum or >= 75
      exhaustion_start = mom_decay_end
      exhaustion_end = exhaustion_start

      # Find when PES first crosses 75 or reaches peak
      opt_idx_ex = option_candles.index { |c| c[:timestamp] >= exhaustion_start } || 0
      option_candles[opt_idx_ex..].each_with_index do |c, offset|
        idx = opt_idx_ex + offset
        # Recalculate PES
        pes, = Research::OptionExpansionAnalyzer.send(:calculate_pes, idx, option_candles, underlying_candles, trade_opp[:breakout_type], expansion_ctx[:entry_price], expansion_ctx[:peak_price])
        if pes >= 75
          exhaustion_end = c[:timestamp]
          break
        end
      end
      exhaustion_end = [exhaustion_end, end_of_day].min
      exhaustion_duration = ((exhaustion_end - exhaustion_start) / 60).round

      # 7. Distribution Phase: End of exhaustion to market close
      dist_start = exhaustion_end
      dist_end = end_of_day
      dist_duration = ((dist_end - dist_start) / 60).round

      {
        compression: { start: comp_start, end: comp_end, duration_mins: 0 },
        auction: { start: auction_start, end: auction_end, duration_mins: auction_duration },
        ignition: { start: ignition_start, end: ignition_end, duration_mins: ignition_duration },
        expansion: { start: expansion_start, end: expansion_end, duration_mins: expansion_duration },
        momentum_decay: { start: mom_decay_start, end: mom_decay_end, duration_mins: mom_decay_duration },
        exhaustion: { start: exhaustion_start, end: exhaustion_end, duration_mins: exhaustion_duration },
        distribution: { start: dist_start, end: dist_end, duration_mins: dist_duration }
      }
    end
  end
end
