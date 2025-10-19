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
          # Get the instrument - query by exchange and segment fields
          instrument = Instrument.find_by(exchange: "nse", segment: "index", security_id: security_id) ||
                      Instrument.find_by(exchange: "bse", segment: "index", security_id: security_id)
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
      @atm_options.each do |index_key, options|
        [ :call, :put ].each do |option_type|
          option = options[option_type]
          next unless option

          begin
            # Subscribe to the option contract
            Live::MarketFeedHub.instance.subscribe(
              segment: option[:segment],
              security_id: option[:security_id]
            )

            Rails.logger.info("[AtmOptions] Subscribed to #{index_key} #{option_type.upcase} #{option[:strike]}")

          rescue StandardError => e
            Rails.logger.error("[AtmOptions] Failed to subscribe to #{index_key} #{option_type}: #{e.message}")
          end
        end
      end
    end

    def unsubscribe_all
      @atm_options.each do |index_key, options|
        [ :call, :put ].each do |option_type|
          option = options[option_type]
          next unless option

          begin
            Live::MarketFeedHub.instance.unsubscribe(
              segment: option[:segment],
              security_id: option[:security_id]
            )
          rescue StandardError => e
            Rails.logger.warn("[AtmOptions] Failed to unsubscribe from #{index_key} #{option_type}: #{e.message}")
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
      # Find the closest strikes to current LTP
      strikes = option_chain.map { |option| option[:strike] }.uniq.sort

      # Find ATM strike (closest to current LTP)
      atm_strike = strikes.min_by { |strike| (strike - current_ltp).abs }

      # Find CALL and PUT options for ATM strike
      call_option = option_chain.find { |option| option[:strike] == atm_strike && option[:option_type] == "CE" }
      put_option = option_chain.find { |option| option[:strike] == atm_strike && option[:option_type] == "PE" }

      {
        call: call_option,
        put: put_option
      }
    end
  end
end
