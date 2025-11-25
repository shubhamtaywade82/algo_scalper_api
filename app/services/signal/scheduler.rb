# frozen_string_literal: true

module Signal
  # rubocop:disable Metrics/ClassLength
  class Scheduler
    DEFAULT_PERIOD = 30 # seconds

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
      # Skip signal generation if market is closed (after 3:30 PM IST)
      return if TradingSession::Service.market_closed?

      signal = evaluate_supertrend_signal(index_cfg)
      return unless signal

      process_signal(index_cfg, signal)
    rescue StandardError => e
      Rails.logger.error("[SignalScheduler] process_index error #{index_cfg[:key]}: #{e.class} - #{e.message}")
      Rails.logger.debug { e.backtrace.first(5).join("\n") }
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
      direction = direction_override || determine_direction(index_cfg)
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

    def evaluate_supertrend_signal(index_cfg)
      instrument = IndexInstrumentCache.instance.get_or_fetch(index_cfg)
      unless instrument
        Rails.logger.warn("[SignalScheduler] Missing instrument for #{index_cfg[:key]}")
        return nil
      end

      indicator_result = Signal::Engine.analyze_multi_timeframe(index_cfg: index_cfg, instrument: instrument)
      unless indicator_result[:status] == :ok
        Rails.logger.warn("[SignalScheduler] Indicator analysis failed for #{index_cfg[:key]}: #{indicator_result[:message]}")
        return nil
      end

      direction = indicator_result[:final_direction]
      if direction.nil? || direction == :avoid
        Rails.logger.debug { "[SignalScheduler] Skipping #{index_cfg[:key]} - indicator direction #{direction || 'nil'}" }
        return nil
      end

      chain_cfg = AlgoConfig.fetch[:chain_analyzer] || {}
      trend_metric = indicator_result.dig(:timeframe_results, :primary, :adx_value)
      candidate = select_candidate_from_chain(index_cfg, direction, chain_cfg, trend_metric)
      return nil unless candidate

      {
        segment: candidate[:segment],
        security_id: candidate[:security_id],
        reason: 'supertrend_adx',
        meta: {
          candidate_symbol: candidate[:symbol],
          lot_size: candidate[:lot_size] || candidate[:lot] || 1,
          direction: direction,
          trend_score: trend_metric,
          source: 'supertrend_adx',
          multiplier: 1
        }
      }
    rescue StandardError => e
      Rails.logger.error("[SignalScheduler] Supertrend signal failed for #{index_cfg[:key]}: #{e.class} - #{e.message}")
      nil
    end

    def select_candidate_from_chain(index_cfg, direction, chain_cfg, trend_score)
      analyzer = Options::ChainAnalyzer.new(
        index: index_cfg,
        data_provider: @data_provider,
        config: chain_cfg
      )

      limit = (chain_cfg[:max_candidates] || 3).to_i
      candidates = analyzer.select_candidates(limit: limit, direction: direction)
      return if candidates.blank?

      candidate = candidates.first.dup
      candidate[:trend_score] ||= trend_score
      candidate
    rescue StandardError => e
      Rails.logger.error("[SignalScheduler] Chain analyzer selection failed: #{e.class} - #{e.message}")
      nil
    end

    def signal_config
      AlgoConfig.fetch[:signals] || {}
    end
  end
  # rubocop:enable Metrics/ClassLength
end
