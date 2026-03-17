# frozen_string_literal: true

module Smc
  # The central orchestrator for SMC logic.
  # Implements the state machine: Trap -> Expansion -> Trend -> Entry Zone
  class Analyzer
    def initialize(series)
      @series = series
      @symbol = series.symbol
      @interval = series.interval
      @store = StructureStore.new(@symbol, @interval)
    end

    def run
      # 1. Update Detectors
      structure = Detectors::Structure.new(@series).to_h
      fvg = Detectors::Fvg.new(@series).to_h
      ob = Detectors::OrderBlocks.new(@series).to_h
      liquidity = Detectors::Liquidity.new(@series).to_h

      # 2. Determine Current State Machine Phase
      phase = determine_phase(structure, fvg, ob, liquidity)

      # 3. Build Analysis Object
      analysis = {
        symbol: @symbol,
        interval: @interval,
        timestamp: Time.zone.now,
        phase: phase,
        structure: structure,
        imbalance: { fvgs: fvg[:active], obs: ob[:active] },
        liquidity: liquidity
      }

      # 4. Store State for next incremental update
      @store.update_state(analysis)

      analysis
    end

    private

    def determine_phase(structure, fvg, ob, liquidity)
      # Trap Detected
      return :trap_detected if liquidity[:buy_side_taken] || liquidity[:sell_side_taken]

      # Expansion (displacement in trend direction)
      return :expansion if fvg[:active].any? || ob[:active].any?

      # Trend Confirmed
      return :trend_confirmed if structure[:last_bos]

      # Neutral if none of the above
      :neutral
    end
  end
end
