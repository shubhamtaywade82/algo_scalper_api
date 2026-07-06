# frozen_string_literal: true

module Strategies
  # Builds an immutable {StrategyContext} for a strategy invocation.
  #
  # One builder per daemon lifetime; #build is called per strategy-cycle.
  # All platform dependencies are injected at construction time so the
  # builder is testable without a full Rails boot.
  class ContextBuilder
    DEFAULT_REPO      = "Candles::Repository"
    DEFAULT_CALC      = "Indicators::Calculator"
    DEFAULT_POSITIONS = "Positions::ActiveCache"
    DEFAULT_SESSION   = "TradingSession::Service"

    def initialize(candle_repository: nil,
                   indicator_calculator: nil,
                   position_cache: nil,
                   session_service: nil,
                   clock: -> { Time.current })
      @candle_repo = candle_repository || Object.const_get(DEFAULT_REPO)
      @indicator_calculator = indicator_calculator || Object.const_get(DEFAULT_CALC)
      @position_cache = position_cache || Object.const_get(DEFAULT_POSITIONS).instance
      @session_service = session_service || Object.const_get(DEFAULT_SESSION)
      @clock = clock
      @logger = nil
    end

    attr_writer :logger

    # Build a context snapshot for the given instrument and strategy.
    #
    # @param instrument [Instrument]
    # @param strategy [Strategies::Base]
    # @param params [Hash] resolved params for this run
    # @param config [Hash] AlgoConfig slice
    # @return [Strategies::StrategyContext]
    def build(instrument:, strategy:, params: {}, config: {})
      instrument_key = instrument.symbol_name
      candles_1m = fetch_candles(instrument_key, "1m")
      calculator = @indicator_calculator.new(candles_1m) if candles_1m

      StrategyContext.new(
        instrument_key: instrument_key,
        candles: CandleSeriesContext.new(@candle_repo, instrument, instrument_key),
        indicators: calculator,
        session: SessionFacade.new(@session_service),
        position: build_position(instrument),
        params: params.freeze,
        clock: @clock,
        config: config.freeze,
        logger: @logger
      )
    end

    private

    def fetch_candles(instrument_key, timeframe)
      from = @clock.call - (60 * 60 * 6) # 6 hours lookback
      to = @clock.call

      @candle_repo.series(
        instrument_key: instrument_key,
        timeframe: timeframe,
        from: from,
        to: to
      )
    end

    def build_position(instrument)
      pos = @position_cache.get(instrument.exchange_segment, instrument.security_id)
      PositionFacade.new(pos)
    end
  end

  # Wraps candles access so strategies can do context.candles("5m").
  class CandleSeriesContext
    def initialize(repo, instrument, instrument_key)
      @repo = repo
      @instrument = instrument
      @instrument_key = instrument_key
    end

    def call(timeframe = "1m")
      from = Time.current - (60 * 60 * 6)
      to = Time.current

      @repo.series(
        instrument_key: @instrument_key,
        timeframe: timeframe,
        from: from,
        to: to,
        include_forming: true,
        instrument: @instrument
      )
    end
  end

  # Immutable wrapper around a live position, or nil-position.
  class PositionFacade
    def initialize(position)
      @position = position
      freeze
    end

    def open?
      @position.present?
    end

    def direction = @position&.position_direction
    def entry_price = @position&.entry_price
    def quantity = @position&.quantity
    def pnl = @position&.pnl
    def pnl_pct = @position&.pnl_pct
    def sl_price = @position&.sl_price
  end

  # Thin adapter exposing TradingSession::Service as an object.
  class SessionFacade
    def initialize(service)
      @service = service
    end

    delegate :market_open?, to: :@service
    def entry_allowed? = @service.entry_allowed?[:allowed]
    def seconds_until_close = @service.seconds_until_session_end
    delegate :should_force_exit?, to: :@service
  end
end
