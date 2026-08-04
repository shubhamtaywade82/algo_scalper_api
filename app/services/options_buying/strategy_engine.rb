# frozen_string_literal: true

module OptionsBuying
  # Strategy Engine that maps regimes to specific entry strategies.
  class StrategyEngine
    # The blueprint: regime -> strategies
    STRATEGIES = {
      trending: [
        Strategies::TripleTfAlignment,
        Strategies::OrbBreakout
      ],
      ranging: [
        Strategies::VcpBreakout
      ],
      low_vix: [
        Strategies::VixExpansion,
        Strategies::IvPercentileConfluence
      ],
      event_day: [], # Future
      late_day: []   # Future
    }.freeze

    def self.evaluate!(index_key:, security_id:, bucket: nil, current_tick: nil)
      new(index_key: index_key, security_id: security_id, bucket: bucket, current_tick: current_tick).evaluate!
    end

    def initialize(index_key:, security_id:, bucket: nil, current_tick: nil)
      @index_key = index_key.to_s.upcase
      @security_id = security_id.to_s
      @bucket = bucket
      @current_tick = current_tick
    end

    def evaluate!
      # Time filter check
      return unless TimeFilter.allowed?(index_key: @index_key)

      spot_ltp = fetch_spot_ltp
      return unless spot_ltp&.positive?

      # VIX Check
      return unless VixFilter.new.valid_for_buying?

      # Regime classification
      regime = RegimeClassifier.detect(@index_key)

      # Select strategies for regime
      applicable_classes = STRATEGIES[regime] || []

      # Always try breakout as fallback if configured or if no regime specific strategy fits perfectly
      # But we will rely on strict mapping per the research

      return if applicable_classes.empty?

      market_state = {
        spot_ltp: spot_ltp,
        regime: regime
      }

      applicable_classes.each do |strategy_class|
        next unless strategy_enabled?(strategy_class)

        strategy = strategy_class.new(index_key: @index_key, security_id: @security_id)

        signal = strategy.check_entry(market_state)
        next unless signal

        # Post-signal checks: Gamma Wall & Slippage
        return process_signal!(signal, strategy)
      end

      nil
    rescue StandardError => e
      Rails.logger.warn("[StrategyEngine] #{@index_key} evaluate! #{e.class} - #{e.message}\n#{e.backtrace&.first(10)&.join("\n")}")
      nil
    end

    private

    def strategy_enabled?(strategy_class)
      # e.g. OptionsBuying::Strategies::OrbBreakout -> orb_breakout
      name = strategy_class.new(index_key: @index_key, security_id: @security_id).name
      enabled_list = Mode.config.dig(:strategies, :enabled) || []
      enabled_list.include?(name)
    end

    def process_signal!(signal, strategy)
      direction = signal[:direction]
      option_sid = signal[:option_security_id]
      spot_ltp = signal[:metrics][:spot_ltp]

      # Run composite TradeScoringEngine
      score_result = TradeScoringEngine.score!(
        index_key: @index_key,
        direction: direction,
        option_security_id: option_sid,
        strategy_name: strategy.name,
        spot_ltp: spot_ltp
      )

      unless score_result[:passed]
        Rails.logger.info(
          "[StrategyEngine] Blocked entry for #{@index_key} #{direction} " \
          "due to low composite score: #{score_result[:score]}/#{score_result.dig(:breakdown, :threshold)}"
        )
        return nil
      end

      # Arm the breakout / entry (we reuse BreakoutEvaluator's arming logic or directly state store)
      # In the existing system, BreakoutEvaluator sets breakout_ready.
      # We will do the same so EntryGuard can pick it up.

      already_armed = StateStore.breakout_ready?(@index_key, direction: direction)
      StateStore.set_breakout_ready!(@index_key, direction: direction)

      unless already_armed
        Rails.logger.info(
          "[StrategyEngine] entry_ready #{direction} #{@index_key} strategy=#{strategy.name} sec=#{option_sid} score=#{score_result[:score]}"
        )
      end

      signal
    end

    def fetch_spot_ltp
      index_sid = IndexConfigLoader.load_indices.find { |c| c[:key].to_s.upcase == @index_key }&.dig(:sid).to_s
      return 0.0 unless index_sid

      if @current_tick && @security_id == index_sid
        @current_tick[:ltp] || @current_tick[:c]
      else
        tick = Live::TickQuery.for_security(segment: 'IDX_I', security_id: index_sid)
        tick ? tick.ltp.to_f : StateStore.cache_snapshot(index_sid)&.dig(:ltp).to_f
      end
    end
  end
end
