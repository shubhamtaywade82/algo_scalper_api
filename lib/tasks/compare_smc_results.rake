# frozen_string_literal: true

namespace :compare do
  desc 'Compare debug:smc_options and smc:scan results for NIFTY'
  task smc_results: :environment do
    puts "\n#{'=' * 80}"
    puts 'COMPARING SMC OPTION CHAIN RESULTS'
    puts "#{'=' * 80}\n"

    # Get NIFTY index config
    indices = IndexConfigLoader.load_indices
    nifty_cfg = indices.find { |idx| idx[:key].to_s.upcase == 'NIFTY' }

    unless nifty_cfg
      puts '❌ NIFTY not found in config'
      exit 1
    end

    puts '📊 Testing with NIFTY config:'
    puts "   Key: #{nifty_cfg[:key]}"
    puts "   SID: #{nifty_cfg[:sid]}"
    puts "   Segment: #{nifty_cfg[:segment]}\n\n"

    # Method 1: Direct instrument (like debug task)
    puts '=' * 80
    puts 'METHOD 1: Direct Instrument (Debug Task Method)'
    puts '=' * 80
    instrument1 = Instrument.find_by_sid_and_segment(
      security_id: nifty_cfg[:sid].to_s,
      segment_code: nifty_cfg[:segment]
    )

    if instrument1
      expiry_list1 = instrument1.expiry_list
      puts "✅ Instrument found: #{instrument1.symbol_name}"
      puts "   Security ID: #{instrument1.security_id}"
      puts "   Segment: #{instrument1.segment}"

      if expiry_list1&.any?
        today = Time.zone.today
        parsed_expiries1 = expiry_list1.compact.filter_map do |raw|
          case raw
          when Date then raw
          when Time, DateTime, ActiveSupport::TimeWithZone then raw.to_date
          when String
            begin
              Date.parse(raw)
            rescue ArgumentError
              nil
            end
          end
        end

        nearest_expiry1 = parsed_expiries1.select { |date| date >= today }.min
        if nearest_expiry1
          days_away1 = (nearest_expiry1 - today).to_i
          puts "\n   📅 Nearest Expiry: #{nearest_expiry1.strftime('%Y-%m-%d')} (#{days_away1} days away)"
        else
          puts "\n   ❌ No future expiry found"
        end

        spot1 = instrument1.ltp&.to_f || instrument1.latest_ltp&.to_f
        puts "   💰 Spot LTP: ₹#{spot1.round(2)}" if spot1&.positive?
      else
        puts '   ❌ No expiry list available'
      end
    else
      puts '❌ Instrument not found'
    end

    # Method 2: Through DerivativeChainAnalyzer (legacy path)
    puts "\n#{'=' * 80}"
    puts 'METHOD 2: Through DerivativeChainAnalyzer (Old Method)'
    puts '=' * 80
    begin
      analyzer2 = Options::DerivativeChainAnalyzer.new(index_key: 'NIFTY')
      puts '✅ DerivativeChainAnalyzer created'

      nearest_expiry_str2 = analyzer2.nearest_expiry
      if nearest_expiry_str2
        nearest_expiry2 = Date.parse(nearest_expiry_str2)
        days_away2 = (nearest_expiry2 - Time.zone.today).to_i
        puts "   📅 Nearest Expiry: #{nearest_expiry_str2} (#{days_away2} days away)"
      else
        puts '   ❌ No expiry found'
      end

      spot2 = analyzer2.spot_ltp
      puts "   💰 Spot LTP: ₹#{spot2.round(2)}" if spot2&.positive?
    rescue StandardError => e
      puts "   ❌ Error: #{e.class} - #{e.message}"
    end

    # Comparison Summary
    puts "\n#{'=' * 80}"
    puts 'COMPARISON SUMMARY'
    puts '=' * 80

    if instrument1 && expiry_list1&.any?
      today = Time.zone.today
      parsed_expiries1 = expiry_list1.compact.filter_map do |raw|
        case raw
        when Date then raw
        when Time, DateTime, ActiveSupport::TimeWithZone then raw.to_date
        when String
          begin
            Date.parse(raw)
          rescue ArgumentError
            nil
          end
        end
      end
      nearest_expiry1 = parsed_expiries1.select { |date| date >= today }.min

      begin
        analyzer2 = Options::DerivativeChainAnalyzer.new(index_key: 'NIFTY')
        nearest_expiry_str2 = analyzer2.nearest_expiry
        nearest_expiry2 = nearest_expiry_str2 ? Date.parse(nearest_expiry_str2) : nil
      rescue StandardError
        nearest_expiry2 = nil
      end

      if nearest_expiry1 && nearest_expiry2
        if nearest_expiry1 == nearest_expiry2
          puts "✅ MATCH: Both methods find the same nearest expiry: #{nearest_expiry1.strftime('%Y-%m-%d')}"
        else
          puts '❌ MISMATCH:'
          puts "   Method 1 (Direct): #{nearest_expiry1.strftime('%Y-%m-%d')}"
          puts "   Method 2 (Analyzer): #{nearest_expiry2.strftime('%Y-%m-%d')}"
        end
      elsif nearest_expiry1
        puts "⚠️  Method 2 failed to find expiry, but Method 1 found: #{nearest_expiry1.strftime('%Y-%m-%d')}"
      elsif nearest_expiry2
        puts "⚠️  Method 1 failed to find expiry, but Method 2 found: #{nearest_expiry2.strftime('%Y-%m-%d')}"
      else
        puts '❌ Both methods failed to find expiry'
      end
    end

    puts "\n#{'=' * 80}"
    puts '✅ Comparison complete'
    puts "#{'=' * 80}\n"
  end
end
