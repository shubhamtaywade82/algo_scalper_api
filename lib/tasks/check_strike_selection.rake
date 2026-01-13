# frozen_string_literal: true

namespace :trading do
  desc 'Diagnose strike selection issues for all indices'
  task check_strike_selection: :environment do
    puts '=' * 80
    puts 'STRIKE SELECTION DIAGNOSTICS'
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

        # Check expiry list
        expiry_list = instrument.expiry_list
        if expiry_list.blank?
          puts '  ❌ No expiry list available'
          puts ''
          next
        end

        expiry_date = Options::ChainAnalyzer.find_next_expiry(expiry_list)
        unless expiry_date
          puts '  ❌ Could not determine next expiry'
          puts "  Available expiries: #{expiry_list.inspect}"
          puts ''
          next
        end

        puts "  Expiry Date: #{expiry_date}"

        # Fetch option chain
        chain_data = begin
          instrument.fetch_option_chain(expiry_date)
        rescue StandardError => e
          puts "  ❌ Error fetching option chain: #{e.class} - #{e.message}"
          puts ''
          next
        end

        unless chain_data && chain_data[:oc].is_a?(Hash)
          puts '  ❌ No option chain data available'
          puts "  Chain data: #{chain_data.inspect}"
          puts ''
          next
        end

        spot = chain_data[:last_price]&.to_f
        unless spot&.positive?
          puts "  ❌ Invalid spot price: #{spot.inspect}"
          puts ''
          next
        end

        puts "  Spot Price: #{spot}"
        puts "  Chain Size: #{chain_data[:oc].size} strikes"
        puts ''

        # Test strike selection for both directions
        %i[bullish bearish].each do |direction|
          side_sym = direction == :bullish ? :CE : :PE
          puts "  Testing #{direction.upcase} (#{side_sym}):"

          # Calculate ATM strike
          strike_step = if %w[SENSEX BANKNIFTY].include?(symbol)
                          100
                        else
                          50 # NIFTY and others
                        end
          atm_strike = ((spot / strike_step.to_f).round * strike_step).to_i
          puts "    ATM Strike: #{atm_strike}"

          # Show strike range in chain
          strikes = chain_data[:oc].keys.map { |k| k.to_f }.sort
          if strikes.any?
            puts "    Chain Strike Range: #{strikes.first.to_i} - #{strikes.last.to_i}"
            puts "    Closest Strike to ATM: #{strikes.min_by { |s| (s - atm_strike).abs }.to_i}"
          end

          # Check if ATM strike exists in chain (try multiple key formats)
          atm_key_formats = [
            atm_strike.to_s,
            format('%.6f', atm_strike.to_f),
            format('%.2f', atm_strike.to_f),
            atm_strike.to_f.to_s,
            atm_strike,
            atm_strike.to_f
          ]

          atm_data = nil
          found_key = nil
          atm_key_formats.each do |key|
            next unless chain_data[:oc].key?(key)

            atm_data = chain_data[:oc][key]
            found_key = key
            break
          end

          # Try fuzzy matching if exact match not found
          unless atm_data
            strikes.each do |strike_float|
              next unless (strike_float - atm_strike.to_f).abs < 0.01

              found_key = format('%.6f', strike_float)
              atm_data = chain_data[:oc][found_key]
              break
            end
          end

          if atm_data.nil?
            puts "    ❌ ATM strike #{atm_strike} NOT FOUND in chain"
            puts "    Available strikes (sample): #{chain_data[:oc].keys.first(5).inspect}"
            puts ''
            next
          end

          side_key = side_sym == :CE ? 'ce' : 'pe'
          option_data = atm_data[side_key]

          if option_data.nil?
            puts "    ❌ #{side_sym} option NOT FOUND for ATM strike #{atm_strike}"
            puts ''
            next
          end

          ltp = option_data['last_price']&.to_f
          oi = option_data['oi']&.to_i
          bid = option_data['top_bid_price']&.to_f
          ask = option_data['top_ask_price']&.to_f

          puts "    LTP: #{ltp.inspect}"
          puts "    OI: #{oi.inspect}"
          puts "    Bid: #{bid.inspect}"
          puts "    Ask: #{ask.inspect}"

          # Check liquidity
          paper_trading = AlgoConfig.fetch.dig(:paper_trading, :enabled) == true
          liquid = if paper_trading && option_data.present?
                     # Paper mode: lenient (allows 0 LTP/OI)
                     true
                   else
                     # Live mode: strict
                     ltp&.positive? && oi&.positive?
                   end

          if liquid
            puts '    ✅ LIQUID (will pass liquidity check)'
          else
            puts '    ❌ NOT LIQUID'
            puts '      - LTP is 0 or nil' unless ltp&.positive?
            puts '      - OI is 0 or nil' unless oi&.positive?
            puts '    ⚠️  Paper mode: Will allow even with 0 LTP/OI' if paper_trading
          end

          # Test StrikeSelector
          selector = Options::StrikeQualification::StrikeSelector.new
          selection = selector.call(
            index_key: symbol,
            side: side_sym,
            permission: :scale_ready,
            spot: spot,
            option_chain: chain_data[:oc],
            trend: direction
          )

          if selection[:ok]
            puts '    ✅ StrikeSelector: OK'
            puts "      Selected Strike: #{selection[:strike]} (#{selection[:strike_type]})"
            puts "      ATM Strike: #{selection[:atm_strike]}"

            # Verify derivative and security_id can be fetched from database
            selected_strike = selection[:strike].to_f
            expiry_date_obj = Date.parse(expiry_date)
            option_type = side_sym.to_s

            require 'bigdecimal'
            strike_bd = BigDecimal(selected_strike.to_s)

            # Try to find derivative using same logic as ChainAnalyzer
            derivative = if instrument.respond_to?(:derivatives)
                           instrument.derivatives.where(
                             expiry_date: expiry_date_obj,
                             option_type: option_type
                           ).detect do |d|
                             BigDecimal(d.strike_price.to_s) == strike_bd
                           end
                         end

            # Fallback: Query by instrument_id
            derivative ||= Derivative.where(
              instrument_id: instrument.id,
              expiry_date: expiry_date_obj,
              option_type: option_type
            ).detect do |d|
              BigDecimal(d.strike_price.to_s) == strike_bd
            end

            # Second fallback: Query by underlying_symbol
            derivative ||= Derivative.where(
              underlying_symbol: instrument.symbol_name,
              exchange: instrument.exchange,
              segment: instrument.segment,
              expiry_date: expiry_date_obj,
              option_type: option_type
            ).detect do |d|
              BigDecimal(d.strike_price.to_s) == strike_bd
            end

            # Third fallback: Use Derivative.find_by_params
            derivative ||= Derivative.find_by_params(
              underlying_symbol: symbol,
              strike_price: selected_strike,
              expiry_date: expiry_date_obj,
              option_type: option_type
            )

            if derivative
              security_id = derivative.security_id.to_s
              puts '    ✅ Derivative Found in Database'
              puts "      Derivative ID: #{derivative.id}"
              puts "      Security ID: #{security_id}"
              puts "      Strike: #{derivative.strike_price} (expected: #{selected_strike})"
              puts "      Expiry: #{derivative.expiry_date} (expected: #{expiry_date_obj})"
              puts "      Option Type: #{derivative.option_type} (expected: #{option_type})"

              # Verify all fields match
              strike_match = BigDecimal(derivative.strike_price.to_s) == strike_bd
              expiry_match = derivative.expiry_date == expiry_date_obj
              option_type_match = derivative.option_type == option_type
              security_id_valid = security_id.present? && !security_id.start_with?('TEST_')

              if strike_match && expiry_match && option_type_match && security_id_valid
                puts '    ✅ Derivative Verification: ALL CHECKS PASSED'
              else
                puts '    ❌ Derivative Verification: MISMATCH DETECTED'
                puts "      Strike match: #{strike_match}"
                puts "      Expiry match: #{expiry_match}"
                puts "      Option type match: #{option_type_match}"
                puts "      Security ID valid: #{security_id_valid}"
              end
            else
              puts '    ❌ Derivative NOT Found in Database'
              puts "      Looking for: strike=#{selected_strike}, expiry=#{expiry_date_obj}, option_type=#{option_type}"

              # Show available strikes in DB
              available_strikes = instrument.derivatives.where(
                expiry_date: expiry_date_obj,
                option_type: option_type
              ).pluck(:strike_price).map(&:to_f).sort

              if available_strikes.any?
                puts "      Available strikes in DB (#{available_strikes.size}): " \
                     "#{available_strikes.first(10).inspect}#{available_strikes.size > 10 ? '...' : ''}"
              else
                puts '      No derivatives found for this expiry and option type'
              end
            end
          else
            puts '    ❌ StrikeSelector: BLOCKED'
            puts "      Reason: #{selection[:reason]}"
          end
          puts ''
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
    puts 'Strike selection will work when:'
    puts '  1. ✅ Option chain data is available'
    puts '  2. ✅ ATM strike exists in chain'
    puts '  3. ✅ Option (CE/PE) exists for ATM strike'
    puts '  4. ✅ Liquidity check passes:'
    puts '     - Paper mode: Strike exists (allows 0 LTP/OI)'
    puts '     - Live mode: LTP > 0 AND OI > 0'
    puts '  5. ✅ Derivative exists in database with matching:'
    puts '     - Strike price'
    puts '     - Expiry date'
    puts '     - Option type (CE/PE)'
    puts '     - Valid security_id (not blank, not TEST_)'
    puts ''
    puts 'If market is closed:'
    puts '  - Option chain might be unavailable'
    puts '  - LTP/OI might be 0 (stale data)'
    puts '  - Paper mode will be more lenient'
    puts ''
    puts 'Common Issues:'
    puts '  - Strike exists in option chain but not in database → Need to sync derivatives'
    puts '  - Derivative found but security_id is invalid → Check derivative data'
    puts '  - Strike/expiry/option_type mismatch → Verify derivative lookup logic'
    puts ''
  end
end
