# frozen_string_literal: true

# Base utilities for service testing scripts
module ServiceTestHelper
  def self.setup_rails
    # Calculate path relative to this file's location
    script_dir = File.expand_path(File.dirname(__FILE__))
    rails_root = File.expand_path(File.join(script_dir, '..', '..'))
    env_file = File.join(rails_root, 'config', 'environment.rb')
    require env_file

    # Ensure we're not in test environment (test env disables DhanHQ)
    # Test scripts should run in development mode to use actual API calls
    unless Rails.env.development? || Rails.env.production?
      puts "⚠️  WARNING: Running in #{Rails.env} environment. DhanHQ may be disabled."
      puts "   Set RAILS_ENV=development to use actual API calls."
    end

    # Check DhanHQ credentials
    check_dhanhq_credentials

    Rails.logger.level = Logger::INFO
  end

  def self.check_dhanhq_credentials
    client_id = ENV['DHANHQ_CLIENT_ID'] || ENV['CLIENT_ID']
    access_token = ENV['DHANHQ_ACCESS_TOKEN'] || ENV['ACCESS_TOKEN']

    unless client_id.present? && access_token.present?
      print_warning("DhanHQ credentials not found in environment variables!")
      print_info("  Required: CLIENT_ID (or DHANHQ_CLIENT_ID) and ACCESS_TOKEN (or DHANHQ_ACCESS_TOKEN)")
      print_info("  Without credentials, API calls will fail.")
      print_info("  Set these in your environment or .env file to use actual DhanHQ API calls.")
    else
      print_info("DhanHQ credentials found - API calls will use actual DhanHQ endpoints")
    end
  end

  def self.print_header(title)
    puts "\n" + "=" * 80
    puts "  #{title}"
    puts "=" * 80
  end

  def self.print_section(title)
    puts "\n--- #{title} ---"
  end

  def self.print_success(message)
    puts "✅ #{message}"
  end

  def self.print_error(message)
    puts "❌ #{message}"
  end

  def self.print_info(message)
    puts "ℹ️  #{message}"
  end

  def self.print_warning(message)
    puts "⚠️  #{message}"
  end

  def self.wait_for(seconds, message = 'Waiting')
    print_info("#{message} (#{seconds}s)...")
    sleep seconds
  end

  def self.check_condition(condition, success_msg, error_msg)
    if condition
      print_success(success_msg)
      true
    else
      print_error(error_msg)
      false
    end
  end

  def self.format_hash(hash, indent = 2)
    hash.map { |k, v| "#{' ' * indent}#{k}: #{v.inspect}" }.join("\n")
  end

  def self.cleanup
    # Override in individual scripts if needed
  end

  # Prerequisite setup methods
  def self.setup_test_watchlist_items
    # Create test watchlist items for NIFTY, BANKNIFTY, SENSEX if they don't exist
    # Note: Instruments use exchange='nse' + segment='index', which generates exchange_segment='IDX_I'
    test_indices = [
      { exchange: 'nse', segment: 'index', security_id: '13', symbol: 'NIFTY', kind: :index_value },
      { exchange: 'nse', segment: 'index', security_id: '25', symbol: 'BANKNIFTY', kind: :index_value },
      { exchange: 'bse', segment: 'index', security_id: '51', symbol: 'SENSEX', kind: :index_value }
    ]

    created_count = 0
    test_indices.each do |idx|
      # Find or create instrument (using exchange + segment, not exchange_segment)
      instrument = Instrument.find_or_create_by!(
        exchange: idx[:exchange],
        segment: idx[:segment],
        security_id: idx[:security_id]
      ) do |inst|
        inst.symbol_name = idx[:symbol]
        inst.display_name = idx[:symbol]
        inst.instrument_type = 'INDEX'
      end

      # Get the exchange_segment (IDX_I) from the instrument
      exchange_seg = instrument.exchange_segment

      # Find or create watchlist item (using exchange_segment for segment field)
      item = WatchlistItem.find_or_initialize_by(
        segment: exchange_seg,
        security_id: idx[:security_id]
      )

      unless item.persisted?
        item.watchable = instrument
        item.kind = idx[:kind]
        item.active = true
        item.label = idx[:symbol]
        item.save!
        created_count += 1
      end
    end

    if created_count > 0
      print_success("Created #{created_count} test watchlist items")
    else
      print_info("Test watchlist items already exist")
    end
  rescue StandardError => e
    print_warning("Watchlist setup failed: #{e.message}")
    print_info("Continuing with existing data...")
  end

  def self.setup_test_instruments
    # Ensure basic instruments exist
    setup_test_watchlist_items # This also creates instruments
  end

  def self.setup_test_derivatives
    # Create test derivatives for NIFTY with ATM and 2 OTM strikes using option chain data
    nifty_instrument = Instrument.find_by(exchange: 'nse', segment: 'index', security_id: '13')
    unless nifty_instrument
      print_info("NIFTY instrument not found - skipping derivatives setup")
      return
    end

    # Get option chain data using Instrument#fetch_option_chain
    begin
      chain_data = nifty_instrument.fetch_option_chain
      unless chain_data && chain_data[:oc]&.any?
        print_warning("No option chain data available - using fallback method")
        return setup_test_derivatives_fallback(nifty_instrument)
      end

      spot_price = chain_data[:last_price]&.to_f
      unless spot_price&.positive?
        spot_price = fetch_ltp(segment: 'IDX_I', security_id: '13', suppress_rate_limit_warning: true) || 26_000.0
        print_info("Using LTP from API as spot price: ₹#{spot_price}")
      else
        print_info("Using spot price from option chain: ₹#{spot_price}")
      end

      # Get available strikes from option chain
      available_strikes = chain_data[:oc].keys.map(&:to_f).sort
      unless available_strikes.any?
        print_warning("No strikes in option chain - using fallback method")
        return setup_test_derivatives_fallback(nifty_instrument)
      end

      # Calculate strike interval from available strikes
      strike_interval = if available_strikes.size >= 2
                         available_strikes[1] - available_strikes[0]
                       else
                         50  # Fallback for NIFTY
                       end

      # Find ATM strike (closest to spot)
      atm_strike = available_strikes.min_by { |s| (s - spot_price).abs }

      # For bullish (CE): ATM, ATM+1, ATM+2 (2 OTM)
      # For bearish (PE): ATM, ATM-1, ATM-2 (2 OTM)
      ce_strikes = [atm_strike]
      pe_strikes = [atm_strike]

      # Add ATM+1, ATM+2 for CE
      [atm_strike + strike_interval, atm_strike + (2 * strike_interval)].each do |strike|
        ce_strikes << strike if available_strikes.include?(strike)
      end

      # Add ATM-1, ATM-2 for PE
      [atm_strike - strike_interval, atm_strike - (2 * strike_interval)].each do |strike|
        pe_strikes << strike if available_strikes.include?(strike)
      end

      print_info("Spot Price: ₹#{spot_price.round(2)}, ATM Strike: #{atm_strike}")
      print_info("CE Strikes: #{ce_strikes.join(', ')} (ATM, ATM+1, ATM+2)")
      print_info("PE Strikes: #{pe_strikes.join(', ')} (ATM, ATM-1, ATM-2)")

      # Get expiry from option chain or instrument
      expiry_date = nil
      if nifty_instrument.expiry_list&.any?
        today = Date.today
        parsed_expiries = nifty_instrument.expiry_list.compact.filter_map do |raw|
          case raw
          when Date then raw
          when Time, DateTime, ActiveSupport::TimeWithZone then raw.to_date
          when String then Date.parse(raw) rescue nil
          end
        end
        expiry_date = parsed_expiries.select { |date| date >= today }.min
      end
      expiry_date ||= Date.today + 7.days

      created_count = 0
      test_types = { 'CE' => ce_strikes, 'PE' => pe_strikes }

      test_types.each do |type, strikes|
        strikes.each_with_index do |strike, index|
          strike_label = if index == 0
                          'ATM'
                        elsif type == 'CE'
                          "ATM+#{index}"
                        else
                          "ATM-#{index}"
                        end

          # Get option data from chain
          option_data = chain_data[:oc][strike.to_s] || chain_data[:oc][strike.to_i.to_s]
          type_data = option_data&.dig(type.downcase)

          # Use security_id from chain data if available, otherwise generate
          security_id = type_data&.dig('security_id')&.to_s || "TEST_#{strike}_#{type}_#{expiry_date.strftime('%Y%m%d')}"

          derivative = Derivative.find_or_initialize_by(
            instrument: nifty_instrument,
            exchange: 'nse',
            segment: 'derivatives',
            security_id: security_id
          )

          unless derivative.persisted?
            derivative.strike_price = strike
            derivative.option_type = type
            derivative.underlying_symbol = 'NIFTY'
            derivative.underlying_security_id = '13'
            derivative.expiry_date = expiry_date
            derivative.lot_size = 75  # NIFTY lot size
            derivative.symbol_name = "NIFTY-#{expiry_date.strftime('%b%Y')}-#{strike.to_i}-#{type}"
            derivative.save!
            created_count += 1
            print_info("  Created #{strike_label}: #{derivative.symbol_name} (Strike: ₹#{strike})")
          end
        end
      end

      if created_count > 0
        print_success("Created #{created_count} test derivatives (ATM and 2 OTM) from option chain")
      else
        print_info("Test derivatives already exist (ATM and 2 OTM)")
      end
    rescue StandardError => e
      print_warning("Derivatives setup failed: #{e.message}")
      print_info("Falling back to manual calculation...")
      setup_test_derivatives_fallback(nifty_instrument)
    end
  end

  def self.setup_test_derivatives_fallback(nifty_instrument)
    # Fallback method using manual calculation
    spot_price = fetch_ltp(segment: 'IDX_I', security_id: '13', suppress_rate_limit_warning: true) || 26_000.0
    strike_interval = 50
    atm_strike = (spot_price / strike_interval).round * strike_interval

    ce_strikes = [atm_strike, atm_strike + strike_interval, atm_strike + (2 * strike_interval)]
    pe_strikes = [atm_strike, atm_strike - strike_interval, atm_strike - (2 * strike_interval)]

    expiry_date = Date.today + 7.days
    if nifty_instrument.expiry_list&.any?
      today = Date.today
      parsed_expiries = nifty_instrument.expiry_list.compact.filter_map do |raw|
        case raw
        when Date then raw
        when Time, DateTime, ActiveSupport::TimeWithZone then raw.to_date
        when String then Date.parse(raw) rescue nil
        end
      end
      next_expiry = parsed_expiries.select { |date| date >= today }.min
      expiry_date = next_expiry if next_expiry
    end

    created_count = 0
    test_types = { 'CE' => ce_strikes, 'PE' => pe_strikes }

    test_types.each do |type, strikes|
      strikes.each_with_index do |strike, index|
        strike_label = if index == 0
                        'ATM'
                      elsif type == 'CE'
                        "ATM+#{index}"
                      else
                        "ATM-#{index}"
                      end

        security_id = "TEST_#{strike}_#{type}_#{expiry_date.strftime('%Y%m%d')}"
        derivative = Derivative.find_or_initialize_by(
          instrument: nifty_instrument,
          exchange: 'nse',
          segment: 'derivatives',
          security_id: security_id
        )

        unless derivative.persisted?
          derivative.strike_price = strike
          derivative.option_type = type
          derivative.underlying_symbol = 'NIFTY'
          derivative.underlying_security_id = '13'
          derivative.expiry_date = expiry_date
          derivative.lot_size = 75
          derivative.symbol_name = "NIFTY-#{expiry_date.strftime('%b%Y')}-#{strike.to_i}-#{type}"
          derivative.save!
          created_count += 1
          print_info("  Created #{strike_label}: #{derivative.symbol_name} (Strike: ₹#{strike})")
        end
      end
    end

    if created_count > 0
      print_success("Created #{created_count} test derivatives (ATM and 2 OTM) - fallback method")
    else
      print_info("Test derivatives already exist (ATM and 2 OTM)")
    end
  rescue StandardError => e
    print_warning("Fallback derivatives setup failed: #{e.message}")
    print_info("Continuing without test derivatives...")
  end

  # Find ATM or 2 OTM derivative for testing using option chain data
  # @param underlying_symbol [String] Underlying symbol (e.g., 'NIFTY')
  # @param option_type [String] 'CE' or 'PE'
  # @param preference [Symbol] :atm, :atm_plus_1, :atm_plus_2 (for CE) or :atm_minus_1, :atm_minus_2 (for PE)
  # @return [Derivative, nil]
  def self.find_atm_or_otm_derivative(underlying_symbol: 'NIFTY', option_type: 'CE', preference: :atm)
    # Get instrument
    index_cfg = AlgoConfig.fetch[:indices]&.find { |idx| idx[:key].to_s.upcase == underlying_symbol.upcase }
    return nil unless index_cfg

    instrument = Instrument.find_by(exchange: 'nse', segment: 'index', security_id: index_cfg[:sid].to_s)
    return nil unless instrument

    # Get option chain data using Instrument#fetch_option_chain
    begin
      chain_data = instrument.fetch_option_chain
      unless chain_data && chain_data[:oc]&.any?
        return find_atm_or_otm_derivative_fallback(instrument, underlying_symbol, option_type, preference, index_cfg)
      end

      spot_price = chain_data[:last_price]&.to_f || fetch_ltp(segment: index_cfg[:segment], security_id: index_cfg[:sid].to_s, suppress_rate_limit_warning: true) || 26_000.0

      # Get available strikes from option chain
      available_strikes = chain_data[:oc].keys.map(&:to_f).sort
      return nil unless available_strikes.any?

      # Calculate strike interval
      strike_interval = available_strikes.size >= 2 ? (available_strikes[1] - available_strikes[0]) : 50

      # Find ATM strike (closest to spot)
      atm_strike = available_strikes.min_by { |s| (s - spot_price).abs }

      # Determine target strike based on preference
      target_strike = case preference
                      when :atm
                        atm_strike
                      when :atm_plus_1, :atm_plus_2
                        raise ArgumentError, "Invalid preference #{preference} for #{option_type}" if option_type == 'PE'
                        offset = preference == :atm_plus_1 ? 1 : 2
                        candidate = atm_strike + (offset * strike_interval)
                        available_strikes.include?(candidate) ? candidate : nil
                      when :atm_minus_1, :atm_minus_2
                        raise ArgumentError, "Invalid preference #{preference} for #{option_type}" if option_type == 'CE'
                        offset = preference == :atm_minus_1 ? 1 : 2
                        candidate = atm_strike - (offset * strike_interval)
                        available_strikes.include?(candidate) ? candidate : nil
                      else
                        atm_strike
                      end

      return nil unless target_strike && available_strikes.include?(target_strike)

      # Get expiry from option chain or instrument
      expiry_date = nil
      if instrument.expiry_list&.any?
        today = Date.today
        parsed_expiries = instrument.expiry_list.compact.filter_map do |raw|
          case raw
          when Date then raw
          when Time, DateTime, ActiveSupport::TimeWithZone then raw.to_date
          when String then Date.parse(raw) rescue nil
          end
        end
        expiry_date = parsed_expiries.select { |date| date >= today }.min
      end
      expiry_date ||= Date.today + 7.days

      # Get option data from chain
      option_data = chain_data[:oc][target_strike.to_s] || chain_data[:oc][target_strike.to_i.to_s]
      type_data = option_data&.dig(option_type.downcase)

      # Find or create derivative
      security_id = type_data&.dig('security_id')&.to_s
      derivative = if security_id
                     Derivative.find_by(
                       underlying_symbol: underlying_symbol,
                       option_type: option_type,
                       security_id: security_id
                     )
                   end

      # If not found by security_id, try by strike and expiry
      derivative ||= Derivative.where(
        underlying_symbol: underlying_symbol,
        option_type: option_type,
        strike_price: target_strike,
        expiry_date: expiry_date
      ).first

      if derivative
        strike_label = if target_strike == atm_strike
                        'ATM'
                      elsif option_type == 'CE'
                        offset = (target_strike - atm_strike) / strike_interval
                        "ATM+#{offset.to_i}"
                      else
                        offset = (atm_strike - target_strike) / strike_interval
                        "ATM-#{offset.to_i}"
                      end
        print_info("Found #{strike_label} derivative: #{derivative.symbol_name} (Strike: ₹#{target_strike})")
      end

      derivative
    rescue StandardError => e
      print_warning("Failed to find ATM/OTM derivative from option chain: #{e.message}")
      find_atm_or_otm_derivative_fallback(instrument, underlying_symbol, option_type, preference, index_cfg)
    end
  end

  def self.find_atm_or_otm_derivative_fallback(instrument, underlying_symbol, option_type, preference, index_cfg)
    # Fallback method using manual calculation
    spot_price = fetch_ltp(segment: index_cfg[:segment], security_id: index_cfg[:sid].to_s, suppress_rate_limit_warning: true) || 26_000.0
    strike_interval = 50
    atm_strike = (spot_price / strike_interval).round * strike_interval

    target_strike = case preference
                    when :atm
                      atm_strike
                    when :atm_plus_1, :atm_plus_2
                      raise ArgumentError, "Invalid preference #{preference} for #{option_type}" if option_type == 'PE'
                      offset = preference == :atm_plus_1 ? 1 : 2
                      atm_strike + (offset * strike_interval)
                    when :atm_minus_1, :atm_minus_2
                      raise ArgumentError, "Invalid preference #{preference} for #{option_type}" if option_type == 'CE'
                      offset = preference == :atm_minus_1 ? 1 : 2
                      atm_strike - (offset * strike_interval)
                    else
                      atm_strike
                    end

    expiry_date = nil
    if instrument.expiry_list&.any?
      today = Date.today
      parsed_expiries = instrument.expiry_list.compact.filter_map do |raw|
        case raw
        when Date then raw
        when Time, DateTime, ActiveSupport::TimeWithZone then raw.to_date
        when String then Date.parse(raw) rescue nil
        end
      end
      expiry_date = parsed_expiries.select { |date| date >= today }.min
    end
    expiry_date ||= Date.today + 7.days

    derivative = Derivative.where(
      underlying_symbol: underlying_symbol,
      option_type: option_type,
      strike_price: target_strike,
      expiry_date: expiry_date
    ).first

    derivative
  rescue StandardError => e
    print_warning("Failed to find ATM/OTM derivative (fallback): #{e.message}")
    nil
  end

  def self.setup_test_position_tracker(paper: true)
    # Create a test position tracker if none exist
    if PositionTracker.active.any?
      print_info("Active position trackers already exist (#{PositionTracker.active.count})")
      return
    end

    # Ensure instrument exists first
    setup_test_instruments

    # Find instrument by exchange + segment (not exchange_segment)
    instrument = Instrument.find_by(exchange: 'nse', segment: 'index', security_id: '13')
    unless instrument
      print_warning("NIFTY instrument not found - cannot create test position")
      return
    end

    # Try to fetch real NIFTY LTP from API for entry price
    entry_price = 25_000.0
    begin
      response = DhanHQ::Models::MarketFeed.ltp({ 'IDX_I' => [13] })
      if response['status'] == 'success'
        tick_data = response.dig('data', 'IDX_I', '13')
        if tick_data && tick_data['last_price']
          entry_price = tick_data['last_price'].to_f
          print_info("Using real NIFTY LTP from API: ₹#{entry_price}")
        end
      end
    rescue StandardError => e
      print_info("Using test entry price (API error: #{e.message})")
    end

    tracker = PositionTracker.create!(
      watchable: instrument,
      instrument: instrument,
      order_no: "TEST-#{Time.current.to_i}",
      security_id: '13',
      symbol: 'NIFTY',
      segment: instrument.exchange_segment, # Use exchange_segment (IDX_I)
      side: 'long',
      status: 'active',
      quantity: 75,
      entry_price: entry_price,
      avg_price: entry_price,
      paper: paper
    )

    print_success("Test position tracker created (ID: #{tracker.id}, Paper: #{paper})")
  rescue StandardError => e
    print_warning("Position tracker setup failed: #{e.message}")
    print_info("Continuing without test position...")
  end

  def self.cleanup_test_data
    # Clean up test data (optional - usually we keep it for other tests)
    # PositionTracker.where("order_no LIKE 'TEST-%'").destroy_all
  end

  # DhanHQ API helper methods
  def self.fetch_ltp(segment:, security_id:, suppress_rate_limit_warning: true)
    # Fetch LTP from DhanHQ API
    # suppress_rate_limit_warning: If true, don't print warnings for 429 rate limit errors
    begin
      response = DhanHQ::Models::MarketFeed.ltp({ segment => [security_id.to_i] })
      if response.is_a?(Hash) && response['status'] == 'success'
        data = response.dig('data', segment, security_id.to_s)
        ltp = data&.dig('last_price')
        return ltp.to_f if ltp
      end
    rescue StandardError => e
      error_msg = e.message.to_s
      is_rate_limit = error_msg.include?('429') || error_msg.include?('rate limit') || error_msg.include?('Rate limit')

      # Suppress warnings for rate limits if requested (they're expected during rapid API calls)
      unless suppress_rate_limit_warning && is_rate_limit
        print_warning("Failed to fetch LTP from API: #{e.message}")
      end
    end
    nil
  end

  def self.fetch_option_chain(underlying_security_id:, segment: 'NSE_FNO')
    # Fetch option chain from DhanHQ API
    begin
      response = DhanHQ::Models::OptionChain.fetch(
        underlying_security_id: underlying_security_id.to_i,
        segment: segment
      )
      return response if response.is_a?(Hash) && response['status'] == 'success'
    rescue StandardError => e
      print_warning("Failed to fetch option chain from API: #{e.message}")
    end
    nil
  end

  def self.fetch_funds
    # Fetch available funds from DhanHQ API
    # Returns nil if fetch fails or data is insufficient
    begin
      response = DhanHQ::Models::Funds.fetch
      if response.is_a?(Hash) && response['status'] == 'success'
        data = response.dig('data')
        # Validate that we have reasonable balance data
        if data
          cash = data.dig('available_cash') || data.dig('cash')
          # Return data only if cash is present and reasonable (> 0)
          return data if cash && cash.to_f.positive?
        end
      end
    rescue StandardError => e
      print_warning("Failed to fetch funds from API: #{e.message}")
    end
    nil
  end

  def self.get_test_capital(fallback: 100_000.0)
    # Get capital for testing - uses API if available, otherwise hardcoded fallback
    real_funds = fetch_funds
    if real_funds
      api_cash = real_funds.dig('available_cash') || real_funds.dig('cash')
      if api_cash && api_cash.to_f > 10_000 # Ensure minimum reasonable balance
        return api_cash.to_f
      end
    end
    # Use hardcoded fallback
    fallback
  end

  def self.create_position_tracker(watchable:, segment:, security_id:, side: 'long', quantity: 1, entry_price: nil, paper: true)
    # Create a PositionTracker record in DB (instead of placing real order)
    # entry_price will be fetched from DhanHQ API if not provided
    entry_price ||= fetch_ltp(segment: segment, security_id: security_id)
    entry_price ||= 25_000.0 # Fallback

    instrument = watchable.is_a?(Derivative) ? watchable.instrument : watchable

    tracker = PositionTracker.create!(
      watchable: watchable,
      instrument: instrument, # Backward compatibility
      order_no: "TEST-#{Time.current.to_i}-#{SecureRandom.hex(3)}",
      security_id: security_id.to_s,
      symbol: watchable.respond_to?(:symbol_name) ? watchable.symbol_name : watchable.to_s,
      segment: segment,
      side: side,
      status: 'active',
      quantity: quantity,
      entry_price: entry_price,
      avg_price: entry_price,
      paper: paper
    )

    print_success("Created PositionTracker (ID: #{tracker.id}, Paper: #{paper}, Entry: ₹#{entry_price})")
    tracker
  rescue StandardError => e
    print_error("Failed to create PositionTracker: #{e.message}")
    nil
  end

  def self.fetch_real_ltp(segment:, security_id:)
    # Alias for fetch_ltp (for backward compatibility)
    fetch_ltp(segment: segment, security_id: security_id)
  end
end

