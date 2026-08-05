# frozen_string_literal: true

module Orchestration
  # Coordinates the entire system pipeline from data to execution
  class StrategyRunner
    def initialize(index_cfg:)
      @index_cfg = index_cfg
      @symbol = index_cfg[:key]
    end

    # Runs a single cycle of the strategy pipeline
    def run
      # 1. Market Data & State
      instrument = IndexInstrumentCache.instance.get_or_fetch(@index_cfg)
      series = instrument.candle_series(interval: '1')
      return unless series&.candles&.any?

      state = MarketState::MarketStateEngine.new(series: series, symbol: @symbol).state
      Rails.logger.info("[StrategyRunner] #{@symbol} State: #{state.inspect}")

      # 2. Entry Filter (Structure + Liquidity + Volatility)
      filter = Entries::EntryFilterEngine.new(series: series, symbol: @symbol)
      direction = state[:trend] == :bullish ? :bullish : :bearish

      unless filter.valid_entry?(direction: direction)
        Rails.logger.debug("[StrategyRunner] #{@symbol} blocked by EntryFilterEngine")
        return
      end

      # 3. Strike Selection (Institutional Prop Model)
      # Handled by Options::ChainAnalyzer which integrates Flow, Gamma, and Prop Selection
      # We use Signal::Engine logic or call pick_strikes_with_qualification directly
      momentum_result = Signal::MomentumValidator.validate(
        instrument: instrument,
        series: series,
        direction: direction
      )

      picks = Options::ChainAnalyzer.pick_strikes_with_qualification(
        index_cfg: @index_cfg,
        direction: direction,
        permission: :scale_ready, # Default permission for runner
        expected_spot_move: series.atr(14).to_f,
        momentum_score: momentum_result.score
      ).picks

      if picks.blank?
        Rails.logger.info("[StrategyRunner] #{@symbol} no qualifying strikes found")
        return
      end

      pick = picks.first
      Rails.logger.info("[StrategyRunner] #{@symbol} Selected Strike: #{pick[:symbol]} (Score: #{pick[:score]})")

      # 4. Execution (Market Order)
      Orders::Executor.place_buy(
        symbol: pick[:symbol],
        qty: pick[:lot_size],
        segment: pick[:segment],
        security_id: pick[:security_id],
        ltp: pick[:ltp]
      )
    end
  end
end
