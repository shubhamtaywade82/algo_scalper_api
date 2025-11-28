# frozen_string_literal: true

require 'singleton'

module Smc
  # Live SMC Service - Continuously monitors indices and generates/executes SMC signals
  #
  # Usage:
  #   service = Smc::LiveSmcService.instance
  #   service.start
  #
  # The service runs in a background thread and:
  # - Monitors configured indices (NIFTY, BANKNIFTY, SENSEX)
  # - Generates SMC signals using Smc::SignalGenerator
  # - Executes signals using Smc::Runner
  # - Respects cooldowns and rate limits per index
  # - Logs all activity with proper context
  class LiveSmcService
    include Singleton

    # Default loop interval (seconds)
    LOOP_INTERVAL = 300 # 5 minutes

    # Delay between processing indices to avoid rate limits
    INDEX_PROCESSING_DELAY = 2.0 # seconds between each index

    # Rate limit handling
    MAX_RETRIES_ON_RATE_LIMIT = 3
    RATE_LIMIT_BACKOFF_BASE = 2.0 # seconds

    def initialize
      @running = false
      @thread = nil
      @mutex = Mutex.new
      @last_signal_time = {} # Track last signal time per index for cooldown
      @rate_limit_errors = {} # Track rate limit errors per index
      @metrics = {
        signals_generated: 0,
        signals_executed: 0,
        signals_rejected: 0,
        errors: 0,
        rate_limit_skips: 0,
        last_run_at: nil
      }
    end

    # Start the service (non-blocking)
    def start
      return if @running

      @mutex.synchronize do
        return if @running

        @running = true
        @thread = Thread.new do
          Thread.current.name = 'smc-live-service'
          run_loop
        end
        Rails.logger.info('[Smc::LiveSmcService] Started')
      end
    end

    # Stop the service
    def stop
      @mutex.synchronize do
        return unless @running

        @running = false
        @thread&.join(2)
        @thread = nil
        Rails.logger.info('[Smc::LiveSmcService] Stopped')
      end
    end

    # Check if service is running
    def running?
      @mutex.synchronize { @running && @thread&.alive? }
    end

    # Get service metrics
    def metrics
      @mutex.synchronize { @metrics.dup }
    end

    # Run once (for manual execution or testing)
    def run_once
      process_all_indices
    end

    private

    def run_loop
      loop do
        break unless @running

        begin
          process_all_indices
          @mutex.synchronize { @metrics[:last_run_at] = Time.current }
        rescue StandardError => e
          @mutex.synchronize { @metrics[:errors] += 1 }
          Rails.logger.error("[Smc::LiveSmcService] Error in run_loop: #{e.class} - #{e.message}")
          Rails.logger.debug { e.backtrace.first(5).join("\n") }
        end

        sleep LOOP_INTERVAL
      end
    rescue StandardError => e
      Rails.logger.error("[Smc::LiveSmcService] Fatal error in run_loop: #{e.class} - #{e.message}")
      @mutex.synchronize { @running = false }
    end

    def process_all_indices
      # Check if SMC is enabled
      smc_config = AlgoConfig.fetch[:smc] || {}
      unless smc_config[:enabled] == true
        Rails.logger.debug { '[Smc::LiveSmcService] SMC is disabled in config' }
        return
      end

      # Get indices from config
      indices = get_configured_indices
      if indices.empty?
        Rails.logger.debug { '[Smc::LiveSmcService] No indices configured for SMC' }
        return
      end

      Rails.logger.debug { "[Smc::LiveSmcService] Processing #{indices.size} indices" }

      indices.each_with_index do |index_cfg, idx|
        # Add delay between indices to avoid rate limits (skip delay for first index)
        sleep(INDEX_PROCESSING_DELAY) if idx > 0

        process_index(index_cfg)
      end
    end

    def get_configured_indices
      # Get indices from AlgoConfig
      all_indices = AlgoConfig.fetch[:indices] || []

      # Filter to only indices that have SMC enabled (if per-index config exists)
      # For now, process all indices - can be filtered later
      all_indices.select do |cfg|
        # Check if index has SMC-specific config or use global SMC config
        smc_enabled = cfg.dig(:smc, :enabled)
        smc_enabled.nil? || smc_enabled == true
      end
    end

    def process_index(index_cfg)
      index_key = index_cfg[:key] || index_cfg['key']
      return unless index_key

      # Check cooldown
      return if cooldown_active?(index_key, index_cfg)

      # Check rate limit cooldown
      if rate_limit_cooldown_active?(index_key)
        @mutex.synchronize { @metrics[:rate_limit_skips] += 1 }
        return
      end

      # Get instrument using IndexInstrumentCache (proper method)
      instrument = IndexInstrumentCache.instance.get_or_fetch(index_cfg)
      unless instrument
        Rails.logger.warn("[Smc::LiveSmcService] Could not get instrument for #{index_key}")
        return
      end

      # Generate signal
      signal = generate_signal(instrument, index_cfg)
      return unless signal

      @mutex.synchronize { @metrics[:signals_generated] += 1 }

      # Execute signal
      result = execute_signal(signal, index_key)
      if result
        @mutex.synchronize do
          @metrics[:signals_executed] += 1
          @last_signal_time[index_key] = Time.current
        end
        Rails.logger.info("[Smc::LiveSmcService] Signal executed for #{index_key}: #{signal[:type]} #{signal[:option_symbol]}")
      else
        @mutex.synchronize { @metrics[:signals_rejected] += 1 }
        Rails.logger.warn("[Smc::LiveSmcService] Signal rejected for #{index_key}: #{signal[:type]} #{signal[:option_symbol]}")
      end
    rescue StandardError => e
      handle_processing_error(e, index_cfg)
    end

    def generate_signal(instrument, index_cfg)
      # Get SMC config (merge global and per-index)
      smc_config = (AlgoConfig.fetch[:smc] || {}).deep_symbolize_keys
      index_smc_config = (index_cfg[:smc] || {}).deep_symbolize_keys
      merged_config = smc_config.merge(index_smc_config)

      # Get interval from config or default
      interval = merged_config[:interval] || index_cfg[:interval] || '5'

      # Generate signal
      generator = SignalGenerator.new(
        instrument,
        interval: interval,
        mode: :live,
        config: merged_config
      )

      signal = generator.generate
      if signal
        Rails.logger.info("[Smc::LiveSmcService] Signal generated for #{instrument.symbol_name}: #{signal[:type]} #{signal[:option_symbol]} @ #{signal[:strike]}")
      else
        Rails.logger.debug { "[Smc::LiveSmcService] No signal generated for #{instrument.symbol_name}" }
      end

      signal
    rescue StandardError => e
      # Check if it's a rate limit error
      if is_rate_limit_error?(e)
        handle_rate_limit_error(e, index_cfg[:key] || index_cfg['key'])
        return nil
      end

      Rails.logger.error("[Smc::LiveSmcService] Signal generation failed for #{instrument.symbol_name}: #{e.class} - #{e.message}")
      nil
    end

    def execute_signal(signal, index_key)
      runner = Runner.new(signal, mode: :live)
      result = runner.execute

      if result
        Rails.logger.info("[Smc::LiveSmcService] Signal executed successfully for #{index_key}")
      else
        Rails.logger.warn("[Smc::LiveSmcService] Signal execution failed for #{index_key}")
      end

      result
    rescue StandardError => e
      Rails.logger.error("[Smc::LiveSmcService] Signal execution error for #{index_key}: #{e.class} - #{e.message}")
      nil
    end

    def cooldown_active?(index_key, index_cfg)
      return false unless @last_signal_time[index_key]

      # Get cooldown from index config or use default
      cooldown_sec = index_cfg[:cooldown_sec] || index_cfg['cooldown_sec'] || 300 # 5 minutes default
      last_time = @last_signal_time[index_key]

      if Time.current - last_time < cooldown_sec
        remaining = cooldown_sec - (Time.current - last_time).to_i
        Rails.logger.debug { "[Smc::LiveSmcService] Cooldown active for #{index_key} (#{remaining}s remaining)" }
        return true
      end

      false
    end

    def handle_processing_error(error, index_cfg)
      index_key = index_cfg[:key] || index_cfg['key'] || 'unknown'

      # Check if it's a rate limit error
      if is_rate_limit_error?(error)
        handle_rate_limit_error(error, index_key)
        @mutex.synchronize { @metrics[:rate_limit_skips] += 1 }
      else
        @mutex.synchronize { @metrics[:errors] += 1 }
        Rails.logger.error("[Smc::LiveSmcService] Error processing #{index_key}: #{error.class} - #{error.message}")
        Rails.logger.debug { error.backtrace.first(5).join("\n") }
      end
    end

    def is_rate_limit_error?(error)
      error_msg = error.message.to_s.downcase
      begin
        error_msg.include?('rate limit') ||
          error_msg.include?('too many requests') ||
          error_msg.include?('dh-904') ||
          error_msg.include?('429') ||
          error.is_a?(DhanHQ::RateLimitError)
      rescue StandardError
        false
      end
    end

    def handle_rate_limit_error(error, index_key)
      @mutex.synchronize do
        current_backoff = @rate_limit_errors[index_key]&.dig(:backoff_seconds) || RATE_LIMIT_BACKOFF_BASE
        retry_count = @rate_limit_errors[index_key]&.dig(:retry_count) || 0

        if retry_count < MAX_RETRIES_ON_RATE_LIMIT
          new_backoff = current_backoff * 2
          @rate_limit_errors[index_key] = {
            last_error: Time.current,
            backoff_seconds: new_backoff,
            retry_count: retry_count + 1
          }
          Rails.logger.warn("[Smc::LiveSmcService] Rate limit for #{index_key} - backing off for #{new_backoff.round(1)}s (retry #{retry_count + 1}/#{MAX_RETRIES_ON_RATE_LIMIT})")
        else
          Rails.logger.error("[Smc::LiveSmcService] Rate limit exceeded max retries for #{index_key} - skipping until next loop")
        end
      end
    end

    def rate_limit_cooldown_active?(index_key)
      return false unless @rate_limit_errors[index_key]

      error_info = @rate_limit_errors[index_key]
      last_error = error_info[:last_error]
      backoff_seconds = error_info[:backoff_seconds] || RATE_LIMIT_BACKOFF_BASE

      if last_error && (Time.current - last_error) < backoff_seconds
        remaining = backoff_seconds - (Time.current - last_error).to_i
        Rails.logger.debug { "[Smc::LiveSmcService] Rate limit cooldown active for #{index_key} (#{remaining}s remaining)" }
        return true
      end

      # Clear rate limit error if cooldown has passed
      @mutex.synchronize { @rate_limit_errors.delete(index_key) }
      false
    end
  end
end
