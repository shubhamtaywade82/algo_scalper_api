# frozen_string_literal: true

module Signal
  # rubocop:disable Metrics/ClassLength
  class Scheduler
    DEFAULT_PERIOD = 30 # seconds
    STRATEGY_MAP = {
      open_interest: Signal::Engines::OpenInterestBuyingEngine,
      momentum_buying: Signal::Engines::MomentumBuyingEngine,
      btst: Signal::Engines::BtstMomentumEngine,
      swing_buying: Signal::Engines::SwingOptionBuyingEngine
    }.freeze

    def initialize(period: DEFAULT_PERIOD, data_provider: nil)
      @period = period
      @running = false
      @thread  = nil
      @mutex   = Mutex.new
      @data_provider = data_provider || default_provider
    end

    def start
      return if @running

      @mutex.synchronize do
        return if @running

        @running = true
      end

      indices = Array(AlgoConfig.fetch[:indices])

      @thread = Thread.new do
        Thread.current.name = 'signal-scheduler'

        loop do
          break unless @running

          begin
            indices.each_with_index do |idx_cfg, idx|
              break unless @running

              sleep(idx.zero? ? 0 : 5)
              process_index(idx_cfg)
            end
          rescue StandardError => e
            Rails.logger.error("[SignalScheduler] #{e.class} - #{e.message}")
          end

          sleep @period
        end
      end
    end

    def stop
      @mutex.synchronize { @running = false }
      @thread&.kill
      @thread = nil
    end

    private

    def process_index(index_cfg)
      enabled_strategies = load_enabled_strategies(index_cfg)
      if enabled_strategies.empty?
        Signal::Engine.run_for(index_cfg)
        return
      end

      signal = evaluate_strategies_priority(index_cfg, enabled_strategies)
      return unless signal

      process_signal(index_cfg, signal)
    rescue StandardError => e
      Rails.logger.error("[SignalScheduler] process_index error #{index_cfg[:key]}: #{e.class} - #{e.message}")
      Rails.logger.debug { e.backtrace.first(5).join("\n") }
    end

    def load_enabled_strategies(index_cfg)
      strategies_cfg = index_cfg[:strategies] || AlgoConfig.fetch[:strategy] || {}
      enabled = []

      STRATEGY_MAP.each do |key, engine_class|
        strategy_cfg = strategies_cfg[key] || {}
        next unless strategy_cfg[:enabled] == true

        priority = strategy_cfg[:priority] || 999
        enabled << {
          key: key,
          engine_class: engine_class,
          config: strategy_cfg,
          priority: priority
        }
      end

      enabled.sort_by { |s| s[:priority] }
    end

    def evaluate_strategies_priority(index_cfg, enabled_strategies)
      chain_cfg = AlgoConfig.fetch[:chain_analyzer] || {}

      return evaluate_with_direction_priority(index_cfg, enabled_strategies, chain_cfg) if direction_first_enabled?

      # Use DerivativeChainAnalyzer for better integration with Derivative records
      analyzer = Options::DerivativeChainAnalyzer.new(
        index_key: index_cfg[:key],
        expiry: nil, # Auto-select nearest expiry
        config: chain_cfg
      )

      direction = determine_direction(index_cfg)
      limit = chain_cfg[:max_candidates] || 1
      candidates = analyzer.select_candidates(limit: limit.to_i, direction: direction)

      return nil if candidates.empty?

      enabled_strategies.each do |strategy|
        candidate = candidates.first
        signal = evaluate_strategy(index_cfg, strategy, candidate)
        next unless signal

        Rails.logger.info(
          "[Scheduler] strategy:#{strategy[:key]} emitted signal:#{signal[:meta][:candidate_symbol]} " \
          "reason:#{signal[:reason]}"
        )
        return signal
      end

      nil
    end

    def evaluate_strategy(index_cfg, strategy, candidate)
      engine = strategy[:engine_class].new(
        index: index_cfg,
        config: strategy[:config],
        option_candidate: candidate
      )

      engine.evaluate
    rescue StandardError => e
      Rails.logger.error(
        "[SignalScheduler] Strategy #{strategy[:key]} evaluation failed: #{e.class} - #{e.message}"
      )
      nil
    end

    def determine_direction(index_cfg)
      direction = index_cfg[:direction] || AlgoConfig.fetch.dig(:strategy, :direction) || :bullish
      direction.to_s.downcase.to_sym
    end

    def process_signal(index_cfg, signal)
      pick = build_pick_from_signal(signal)
      direction_override = signal.dig(:meta, :direction)&.to_sym
      direction = if direction_first_enabled? && direction_override
                    direction_override
                  else
                    determine_direction(index_cfg)
                  end
      multiplier = signal[:meta][:multiplier] || 1

      result = Entries::EntryGuard.try_enter(
        index_cfg: index_cfg,
        pick: pick,
        direction: direction,
        scale_multiplier: multiplier
      )

      return if result

      Rails.logger.warn(
        "[Scheduler] EntryGuard rejected signal for #{index_cfg[:key]}: #{signal[:meta][:candidate_symbol]}"
      )
    end

    def build_pick_from_signal(signal)
      segment = signal[:segment] || signal[:exchange_segment]
      {
        segment: segment,
        security_id: signal[:security_id],
        symbol: signal[:meta][:candidate_symbol] || 'UNKNOWN',
        lot_size: signal[:meta][:lot_size] || 1,
        ltp: nil # Will be resolved by EntryGuard
      }
    end

    def default_provider
      Providers::DhanhqProvider.new
    rescue NameError
      nil
    end

    def evaluate_with_direction_priority(index_cfg, enabled_strategies, chain_cfg)
      trend_config = signal_config
      dir_ctx = Signal::TrendScorer.compute_direction(
        index_cfg: index_cfg,
        primary_tf: trend_config[:primary_timeframe] || '1m',
        confirmation_tf: trend_config[:confirmation_timeframe] || '5m',
        bullish_threshold: direction_thresholds[:bullish],
        bearish_threshold: direction_thresholds[:bearish]
      )
      direction = dir_ctx[:direction]
      trend_score = dir_ctx[:trend_score]

      unless direction
        Rails.logger.debug { "[SignalScheduler] Skipping #{index_cfg[:key]} - direction undetermined" }
        return nil
      end

      candidate = select_candidate_for_direction(index_cfg, direction, trend_score, chain_cfg)
      return nil unless candidate

      enabled_strategies.each do |strategy|
        signal = evaluate_strategy(index_cfg, strategy, candidate)
        next unless signal

        signal[:meta] ||= {}
        signal[:meta][:direction] ||= direction
        signal[:meta][:trend_score] ||= trend_score if trend_score
        return signal
      end

      nil
    end

    def select_candidate_for_direction(index_cfg, direction, trend_score, chain_cfg)
      selector = Options::StrikeSelector.new
      selection = selector.select(
        index_key: index_cfg[:key],
        direction: direction,
        trend_score: trend_score,
        config: chain_cfg
      )
      return unless selection

      normalize_candidate(selection)
    end

    def normalize_candidate(selection)
      candidate = selection.dup
      candidate[:segment] ||= candidate[:exchange_segment]
      candidate[:type] ||= candidate[:option_type]
      candidate[:strike] ||= candidate[:strike_price]
      candidate[:trend_score] ||= candidate[:score]
      candidate
    end

    def direction_first_enabled?
      feature_flags[:enable_direction_before_chain] == true
    end

    def feature_flags
      AlgoConfig.fetch[:feature_flags] || {}
    end

    def signal_config
      AlgoConfig.fetch[:signals] || {}
    end

    def direction_thresholds
      thresholds = signal_config[:direction_thresholds] || {}
      {
        bullish: thresholds[:bullish]&.to_f || 14.0,
        bearish: thresholds[:bearish]&.to_f || 7.0
      }
    end
  end
  # rubocop:enable Metrics/ClassLength
end
