# frozen_string_literal: true

module Smc
  module Confluence
    # Multi-timeframe last-bar payload from {Smc::Confluence::Engine} (Pine parity).
    # JSON-serializable for APIs, Redis, and AI payloads (matches delta_exchange_bot shape).
    class MtfDigest
      class << self
        # @param symbol [String]
        # @param timeframe_candles [Hash] resolution string => array of OHLCV hashes (oldest first)
        # @param configuration [Configuration]
        # @return [Hash]
        def from_timeframe_candles(symbol:, timeframe_candles:, configuration: Configuration.new)
          new(
            symbol: symbol,
            timeframe_candles: timeframe_candles,
            configuration: configuration
          ).to_h
        end

        # Fetches candles per interval via {Instrument#candles} (Dhan OHLC).
        #
        # @param instrument [Instrument]
        # @param htf [String] e.g. '60'
        # @param mtf [String] e.g. '15'
        # @param ltf [String] e.g. '5'
        # @param sleep_between [Float] seconds between fetches (rate limit courtesy)
        # @param configuration [Configuration]
        def build_from_instrument(instrument:, htf:, mtf:, ltf:, sleep_between: 0.0,
                                  configuration: Configuration.new)
          tf_candles = {}
          [htf, mtf, ltf].each_with_index do |interval, idx|
            sleep(sleep_between) if idx.positive? && sleep_between.positive?

            series = instrument.candles(interval: interval)
            tf_candles[interval.to_s] = CandleRows.from_series(series)
          end

          from_timeframe_candles(
            symbol: instrument.symbol_name.to_s,
            timeframe_candles: tf_candles,
            configuration: configuration
          )
        end
      end

      def initialize(symbol:, timeframe_candles:, configuration:)
        @symbol = symbol
        @timeframe_candles = timeframe_candles.transform_keys(&:to_s)
        @configuration = configuration
      end

      def to_h
        timeframes = {}
        alignment = {
          'long_signal' => {},
          'short_signal' => {},
          'structure_bias' => {},
          'long_score' => {},
          'short_score' => {},
          'choch_bull' => {},
          'choch_bear' => {},
          'liq_sweep_bull' => {},
          'liq_sweep_bear' => {},
          'pdh_sweep' => {},
          'pdl_sweep' => {}
        }

        @timeframe_candles.each do |resolution, candles|
          next unless candles.is_a?(Array) && candles.any?

          series = Engine.run(candles, configuration: @configuration)
          last = series.last
          next unless last

          raw = last.serialize
          timeframes[resolution] = {
            'resolution' => resolution,
            'candle_count' => candles.size,
            'last_bar_at' => Time.zone.at(candles.last[:timestamp].to_i).utc.iso8601,
            'last_close' => round_price(candles.last[:close]),
            'confluence' => round_confluence(raw)
          }

          alignment['long_signal'][resolution] = last.long_signal
          alignment['short_signal'][resolution] = last.short_signal
          alignment['structure_bias'][resolution] = last.structure_bias
          alignment['long_score'][resolution] = last.long_score
          alignment['short_score'][resolution] = last.short_score
          alignment['choch_bull'][resolution] = last.choch_bull
          alignment['choch_bear'][resolution] = last.choch_bear
          alignment['liq_sweep_bull'][resolution] = last.liq_sweep_bull
          alignment['liq_sweep_bear'][resolution] = last.liq_sweep_bear
          alignment['pdh_sweep'][resolution] = last.pdh_sweep
          alignment['pdl_sweep'][resolution] = last.pdl_sweep
        end

        {
          'schema_version' => 1,
          'kind' => 'smc_confluence_mtf',
          'symbol' => @symbol,
          'generated_at_utc' => Time.current.utc.iso8601,
          'source' => 'Smc::Confluence::Engine',
          'timeframes' => timeframes,
          'alignment' => alignment,
          'notes' => [
            'Each timeframe confluence object is the last bar in the fetched window (Pine-parity scoring).',
            'PDH/PDL populate after a UTC calendar day rollover within the window.',
            'Legacy SMC (BiasEngine / Context) remains separate; this object is the confluence engine only.'
          ]
        }
      end

      private

      def round_confluence(h)
        return nil unless h.is_a?(Hash)

        c = h.stringify_keys
        %w[pdh pdl poc vah val atr14].each do |key|
          c[key] = round_price(c[key]) if c.key?(key)
        end
        %w[tl_bear_break tl_bull_break pdh_sweep pdl_sweep].each do |key|
          c[key] = c[key] ? true : false if c.key?(key)
        end
        c
      end

      def round_price(value)
        return nil if value.nil?

        value.to_d.round(4).to_f
      end
    end
  end
end
