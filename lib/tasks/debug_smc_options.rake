# frozen_string_literal: true

namespace :debug do
  desc 'Debug SMC option chain fetching - verify expiry detection and chain loading'
  task smc_options: :environment do
    require 'app/services/index_config_loader'
    require 'app/services/options/derivative_chain_analyzer'

    puts "\n=== SMC Option Chain Debug ===\n\n"

    # Load indices from config
    indices = IndexConfigLoader.load_from_config
    puts "📊 Loaded #{indices.size} indices from config\n\n"

    indices.each do |index_cfg|
      symbol_name = index_cfg[:key] || index_cfg[:symbol] || 'UNKNOWN'
      puts '=' * 80
      puts "🔍 Analyzing: #{symbol_name}"
      puts '=' * 80

      begin
        # Step 1: Create analyzer
        analyzer = Options::DerivativeChainAnalyzer.new(index_key: symbol_name)
        puts "✅ Created DerivativeChainAnalyzer for #{symbol_name}"

        # Step 2: Get instrument and expiry list
        instrument = IndexInstrumentCache.instance.get_or_fetch(index_cfg)
        unless instrument
          puts "❌ No instrument found for #{symbol_name}"
          next
        end

        puts "\n📋 Instrument Details:"
        puts "   - Symbol: #{instrument.symbol_name}"
        puts "   - Security ID: #{instrument.security_id}"
        puts "   - Segment: #{instrument.segment}"

        # Step 3: Check expiry list
        expiry_list = instrument.expiry_list
        if expiry_list.blank?
          puts "\n❌ No expiry list available for #{symbol_name}"
          next
        end

        puts "\n📅 Available Expiry Dates:"
        expiry_list.each_with_index do |exp, idx|
          parsed = begin
            case exp
            when Date then exp
            when Time, DateTime, ActiveSupport::TimeWithZone then exp.to_date
            when String then Date.parse(exp)
            end
          rescue ArgumentError
            nil
          end

          if parsed
            days_away = (parsed - Time.zone.today).to_i
            status = if days_away.negative?
                       '❌ PAST'
                     else
                       days_away.zero? ? '🟡 TODAY' : "✅ #{days_away} days"
                     end
            puts "   #{idx + 1}. #{parsed.strftime('%Y-%m-%d')} (#{status})"
          else
            puts "   #{idx + 1}. #{exp.inspect} (⚠️  Invalid format)"
          end
        end

        # Step 4: Find nearest expiry
        nearest_expiry_str = analyzer.nearest_expiry
        if nearest_expiry_str
          nearest_expiry = Date.parse(nearest_expiry_str)
          days_away = (nearest_expiry - Time.zone.today).to_i
          puts "\n🎯 Nearest Expiry: #{nearest_expiry_str} (#{days_away} days away)"
        else
          puts "\n❌ Could not determine nearest expiry"
          next
        end

        # Step 5: Get spot LTP
        spot = analyzer.spot_ltp
        if spot&.positive?
          puts "💰 Spot LTP: ₹#{spot.round(2)}"
        else
          puts "⚠️  Spot LTP: Not available (#{spot.inspect})"
        end

        # Step 6: Load option chain for nearest expiry
        puts "\n🔗 Loading Option Chain for expiry #{nearest_expiry_str}..."
        chain = analyzer.load_chain_for_expiry(nearest_expiry, spot)

        if chain.empty?
          puts "❌ Option chain is EMPTY for #{symbol_name} expiry #{nearest_expiry_str}"

          # Check if derivatives exist in DB
          derivative_count = Derivative.where(
            underlying_symbol: symbol_name,
            expiry_date: nearest_expiry
          ).where.not(option_type: [nil, '']).count

          puts "\n   📊 Database Check:"
          puts "      - Derivatives in DB for #{symbol_name} #{nearest_expiry_str}: #{derivative_count}"

          if derivative_count.zero?
            puts '      ⚠️  No derivatives found in database for this expiry'
            puts "      💡 Suggestion: Check if derivatives are being synced for #{symbol_name}"
          else
            puts '      ⚠️  Derivatives exist in DB but chain is empty'
            puts '      💡 Suggestion: Check DerivativeChainAnalyzer#load_chain_for_expiry logic'
          end
        else
          puts "✅ Option chain loaded: #{chain.size} options found"

          # Show sample strikes
          strikes = chain.filter_map { |opt| opt[:strike] }.uniq.sort
          puts "\n   📊 Strike Range:"
          puts "      - Min: ₹#{strikes.first}" if strikes.any?
          puts "      - Max: ₹#{strikes.last}" if strikes.any?
          puts "      - Count: #{strikes.size} unique strikes"

          # Show sample options
          puts "\n   📋 Sample Options (first 5):"
          chain.first(5).each do |opt|
            puts "      - #{opt[:option_type]} #{opt[:strike]}: LTP=₹#{opt[:ltp]}, OI=#{opt[:oi]}"
          end
        end

        # Step 7: Calculate strike rounding
        strike_rounding = case symbol_name.to_s.upcase
                          when 'NIFTY' then 50
                          when 'SENSEX', 'BANKNIFTY' then 100
                          else 50
                          end

        if spot&.positive?
          puts "\n🎲 Strike Calculation Example (LTP: ₹#{spot.round(2)}, Rounding: #{strike_rounding}):"
          atm_strike = (spot / strike_rounding).round * strike_rounding
          puts "   - ATM: ₹#{atm_strike}"
          puts "   - ATM+1: ₹#{atm_strike + strike_rounding}"
          puts "   - ATM-1: ₹#{atm_strike - strike_rounding}"
        end
      rescue StandardError => e
        puts "\n❌ Error analyzing #{symbol_name}:"
        puts "   #{e.class}: #{e.message}"
        puts "   #{e.backtrace.first(3).join("\n   ")}"
      end

      puts "\n"
    end

    puts '=' * 80
    puts '✅ Debug complete'
    puts '=' * 80
  end
end
