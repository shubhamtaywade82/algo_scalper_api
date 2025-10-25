# frozen_string_literal: true

module Live
  class AtmOptionsService
    include Singleton

    def initialize
      @atm_options = {}
      @lock = Mutex.new
      @service_started = false
    end

    def start!
      @lock.synchronize do
        @service_started = true
        load_atm_options
        subscribe_to_options
        Rails.logger.info("[AtmOptions] Started ATM options service with #{@atm_options.size} contracts")
      end
    end

    def stop!
      @lock.synchronize do
        @service_started = false
        unsubscribe_all
        @atm_options.clear
        Rails.logger.info("[AtmOptions] Stopped ATM options service")
      end
    end

    def get_atm_option(index_key, option_type)
      @atm_options.dig(index_key, option_type)
    end

    def running?
      # Service is considered running if it has been started, even with 0 contracts
      # This prevents 503 errors when API calls fail but service is functional
      @service_started || false
    end

    private

    def load_atm_options
      # Load ATM options for each configured index
      algo_config = Rails.application.config.x.algo
      return unless algo_config&.indices

      algo_config.indices.each do |index_config|
        index_key = index_config[:key]
        segment = index_config[:segment]
        security_id = index_config[:sid]

        Rails.logger.info("[AtmOptions] Loading ATM options for #{index_key}")

        begin
          instrument = Instrument.find_by_sid_and_segment(
            security_id: security_id,
            segment_code: segment,
            symbol_name: index_key
          )
          next unless instrument

          # Get current LTP to determine ATM strike
          current_ltp = instrument.ltp || instrument.fetch_ltp_from_api
          next unless current_ltp

          # Get next expiry date
          next_expiry = get_next_expiry_date
          next unless next_expiry

          # Get option chain
          option_chain = instrument.fetch_option_chain(next_expiry)
          next unless option_chain&.any?

          # Find ATM strikes
          atm_strikes = find_atm_strikes(option_chain, current_ltp)
          next unless atm_strikes[:call] && atm_strikes[:put]

          # Store ATM option contracts
          @atm_options[index_key] = {
            call: atm_strikes[:call],
            put: atm_strikes[:put],
            current_ltp: current_ltp,
            expiry: next_expiry
          }

          Rails.logger.info("[AtmOptions] #{index_key} ATM: CALL #{atm_strikes[:call][:strike]} PUT #{atm_strikes[:put][:strike]}")

        rescue StandardError => e
          Rails.logger.error("[AtmOptions] Failed to load ATM options for #{index_key}: #{e.message}")
        end
      end
    end

    def subscribe_to_options
      # Collect all options for batch subscription
      all_options = []

      @atm_options.each do |index_key, options|
        [ :call, :put ].each do |option_type|
          option = options[option_type]
          next unless option

          all_options << {
            segment: option[:segment],
            security_id: option[:security_id],
            index_key: index_key,
            option_type: option_type,
            strike: option[:strike]
          }
        end
      end

      return if all_options.empty?

      begin
        # Use batch subscription for efficiency
        Live::MarketFeedHub.instance.subscribe_many(all_options)
        Rails.logger.info("[AtmOptions] Batch subscribed to #{all_options.count} options")

        # Log individual subscriptions for debugging
        all_options.each do |option|
          Rails.logger.info("[AtmOptions] Subscribed to #{option[:index_key]} #{option[:option_type].upcase} #{option[:strike]}")
        end

      rescue StandardError => e
        Rails.logger.error("[AtmOptions] Failed to batch subscribe to options: #{e.message}")

        # Fallback to individual subscriptions
        all_options.each do |option|
          begin
            Live::MarketFeedHub.instance.subscribe(
              segment: option[:segment],
              security_id: option[:security_id]
            )
            Rails.logger.info("[AtmOptions] Fallback subscribed to #{option[:index_key]} #{option[:option_type].upcase} #{option[:strike]}")
          rescue StandardError => fallback_error
            Rails.logger.error("[AtmOptions] Failed to subscribe to #{option[:index_key]} #{option[:option_type]}: #{fallback_error.message}")
          end
        end
      end
    end

    def unsubscribe_all
      # Collect all options for batch unsubscription
      all_options = []

      @atm_options.each do |index_key, options|
        [ :call, :put ].each do |option_type|
          option = options[option_type]
          next unless option

          all_options << {
            segment: option[:segment],
            security_id: option[:security_id],
            index_key: index_key,
            option_type: option_type,
            strike: option[:strike]
          }
        end
      end

      return if all_options.empty?

      begin
        # Use batch unsubscription for efficiency
        Live::MarketFeedHub.instance.unsubscribe_many(all_options)
        Rails.logger.info("[AtmOptions] Batch unsubscribed from #{all_options.count} options")

        # Log individual unsubscriptions for debugging
        all_options.each do |option|
          Rails.logger.info("[AtmOptions] Unsubscribed from #{option[:index_key]} #{option[:option_type].upcase} #{option[:strike]}")
        end

      rescue StandardError => e
        Rails.logger.error("[AtmOptions] Failed to batch unsubscribe from options: #{e.message}")

        # Fallback to individual unsubscriptions
        all_options.each do |option|
          begin
            Live::MarketFeedHub.instance.unsubscribe(
              segment: option[:segment],
              security_id: option[:security_id]
            )
            Rails.logger.info("[AtmOptions] Fallback unsubscribed from #{option[:index_key]} #{option[:option_type].upcase} #{option[:strike]}")
          rescue StandardError => fallback_error
            Rails.logger.warn("[AtmOptions] Failed to unsubscribe from #{option[:index_key]} #{option[:option_type]}: #{fallback_error.message}")
          end
        end
      end
    end

    def get_next_expiry_date
      # Get next Thursday (standard expiry for Indian indices)
      today = Date.current
      next_thursday = today + ((4 - today.wday) % 7).days

      # If today is Thursday and market is still open, use next Thursday
      if today.wday == 4 && Time.current.hour < 15
        next_thursday += 7.days
      end

      next_thursday.strftime("%Y-%m-%d")
    end

    def find_atm_strikes(option_chain, current_ltp)
      # Ensure option_chain is an array and has the expected structure
      return { call: nil, put: nil } unless option_chain.is_a?(Array) && option_chain.any?

      # Find the closest strikes to current LTP
      strikes = option_chain.map do |option|
        if option.is_a?(Hash) && option[:strike]
          option[:strike]
        elsif option.respond_to?(:strike)
          option.strike
        else
          Rails.logger.warn("[AtmOptions] Invalid option structure: #{option.inspect}")
          nil
        end
      end.compact.uniq.sort

      return { call: nil, put: nil } if strikes.empty?

      # Find ATM strike (closest to current LTP)
      atm_strike = strikes.min_by { |strike| (strike - current_ltp).abs }

      # Find CALL and PUT options for ATM strike
      call_option = option_chain.find do |option|
        strike = if option.is_a?(Hash)
                   option[:strike]
                 elsif option.respond_to?(:strike)
                   option.strike
                 end
        option_type = if option.is_a?(Hash)
                        option[:option_type]
                      elsif option.respond_to?(:option_type)
                        option.option_type
                      end
        strike == atm_strike && option_type == "CE"
      end

      put_option = option_chain.find do |option|
        strike = if option.is_a?(Hash)
                   option[:strike]
                 elsif option.respond_to?(:strike)
                   option.strike
                 end
        option_type = if option.is_a?(Hash)
                        option[:option_type]
                      elsif option.respond_to?(:option_type)
                        option.option_type
                      end
        strike == atm_strike && option_type == "PE"
      end

      {
        call: call_option,
        put: put_option
      }
    end
  end
end
