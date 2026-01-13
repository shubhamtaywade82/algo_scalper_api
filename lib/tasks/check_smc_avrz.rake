# frozen_string_literal: true

namespace :trading do
  desc 'Check SMC + AVRZ states and permission resolution for all indices'
  task check_smc_avrz: :environment do
    puts '=' * 80
    puts 'SMC + AVRZ PERMISSION DIAGNOSTICS'
    puts '=' * 80
    puts ''

    indices = IndexConfigLoader.load_indices
    if indices.empty?
      puts '⚠️  No indices configured'
      return
    end

    indices.each do |index_cfg|
      symbol = index_cfg[:key]
      puts "Index: #{symbol}"
      puts '-' * 80

      begin
        instrument = IndexInstrumentCache.instance.get_or_fetch(index_cfg)
        unless instrument
          puts '  ❌ Instrument not found'
          puts ''
          next
        end

        # Get permission
        permission = Trading::PermissionResolver.resolve(symbol: symbol, instrument: instrument)
        puts "  Permission: #{permission.to_s.upcase}"

        # Get detailed SMC + AVRZ info
        htf_series = instrument.candle_series(interval: Smc::BiasEngine::HTF_INTERVAL)
        mtf_series = instrument.candle_series(interval: Smc::BiasEngine::MTF_INTERVAL)
        ltf_series = instrument.candle_series(interval: Smc::BiasEngine::LTF_INTERVAL)

        if htf_series&.candles&.any? && mtf_series&.candles&.any? && ltf_series&.candles&.any?
          htf = Smc::Context.new(htf_series)
          mtf = Smc::Context.new(mtf_series)
          ltf = Smc::Context.new(ltf_series)

          # AVRZ state
          avrz_state = begin
            candles = ltf_series.candles || []
            if candles.size < 10
              :dead
            else
              compressed = Entries::RangeUtils.compressed?(candles.last(6), threshold_pct: 0.06)
              if compressed
                :compressed
              else
                rejection = Avrz::Detector.new(ltf_series).rejection?
                rejection ? :expanding_early : :dead
              end
            end
          rescue StandardError
            :dead
          end

          # SMC structure
          htf_trend = htf.trend
          mtf_struct = mtf.structure.to_h
          ltf_struct = ltf.internal_structure.to_h

          structure_state = if htf_trend.to_sym == :range
                              :range
                            elsif %i[bullish bearish].include?(htf_trend.to_sym)
                              :trend
                            else
                              :neutral
                            end

          fvg_gaps = Array(ltf.fvg.to_h[:gaps])
          liquidity_h = ltf.liquidity.to_h

          puts ''
          puts '  SMC Analysis:'
          puts "    HTF Trend: #{htf_trend}"
          puts "    Structure State: #{structure_state}"
          puts "    BOS Recent: #{mtf_struct[:bos] == true}"
          puts "    Displacement (FVG gaps): #{fvg_gaps.any?} (#{fvg_gaps.size} gaps)"
          puts "    Liquidity Event Resolved: #{liquidity_h[:sweep] == true}"
          puts "    Active Liquidity Trap: #{liquidity_h[:equal_highs] == true || liquidity_h[:equal_lows] == true}"
          puts "    Follow Through: #{ltf_struct[:bos] == true}"

          puts ''
          puts '  AVRZ Analysis:'
          puts "    State: #{avrz_state}"
          puts "    LTF Candles: #{ltf_series.candles.size}"

          puts ''
          puts '  Permission Resolution:'
          if permission == :blocked
            puts '    ❌ BLOCKED - Reasons:'
            puts '      - AVRZ state is :dead' if avrz_state == :dead
            if structure_state.in?(%i[range neutral])
              puts "      - SMC structure state is #{structure_state} (must be :trend)"
            end
            puts '      - No BOS (Break of Structure) detected recently' unless mtf_struct[:bos] == true
          elsif permission == :execution_only
            puts '    ⚠️  EXECUTION_ONLY - 1-lot scalping allowed, no scaling'
          elsif permission == :scale_ready
            puts '    ✅ SCALE_READY - Scaling allowed'
          elsif permission == :full_deploy
            puts '    ✅✅ FULL_DEPLOY - Full capital deployment allowed'
          end
        else
          puts '  ❌ Missing candle data:'
          puts "    HTF candles: #{htf_series&.candles&.size || 0}"
          puts "    MTF candles: #{mtf_series&.candles&.size || 0}"
          puts "    LTF candles: #{ltf_series&.candles&.size || 0}"
        end
      rescue StandardError => e
        puts "  ❌ ERROR: #{e.class} - #{e.message}"
        puts e.backtrace.first(3).join("\n")
      end

      puts ''
    end

    puts '=' * 80
    puts 'SUMMARY'
    puts '=' * 80
    puts ''
    puts 'For trades to be allowed, you need:'
    puts ''
    puts 'MINIMUM (execution_only):'
    puts '  - Range markets: displacement (FVG gaps) present'
    puts '  - Trend markets: structure_state = :trend, BOS recent = true'
    puts '  - AVRZ: :compressed or better (defaults to :compressed, rarely :dead)'
    puts ''
    puts 'BETTER (scale_ready):'
    puts '  - AVRZ: :expanding_early'
    puts '  - SMC: structure_state = :trend'
    puts '  - SMC: BOS recent = true'
    puts '  - SMC: displacement = true'
    puts '  - SMC: active_liquidity_trap = false'
    puts ''
    puts 'BEST (full_deploy):'
    puts '  - AVRZ: :expanding'
    puts '  - SMC: structure_state = :trend'
    puts '  - SMC: BOS recent = true'
    puts '  - SMC: displacement = true'
    puts '  - SMC: (trap_resolved OR (BOS + follow_through))'
    puts ''
    puts 'NOTE: Range markets with displacement now allow execution_only (1-lot trades)'
    puts '      even without BOS, making the system more lenient for range-bound conditions.'
    puts ''
  end
end
