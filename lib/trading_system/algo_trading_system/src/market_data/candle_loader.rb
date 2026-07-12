# frozen_string_literal: true

require 'csv'
require 'time'
require_relative 'candle'

module MarketData
  # Loads historical candle data for backtesting or chart initialization
  class CandleLoader
    class << self
      def load_history(symbol:, from_time:, to_time:, timeframe: '5m', source: :csv, candle_class: Candle)
        return [] unless source == :csv

        load_from_csv(
          symbol: symbol,
          from_time: from_time,
          to_time: to_time,
          timeframe: timeframe,
          candle_class: candle_class
        )
      end

      private

      def load_from_csv(symbol:, from_time:, to_time:, timeframe:, candle_class:)
        filepath = "spec/fixtures/candles/#{symbol.downcase}_#{timeframe}.csv"
        return [] unless File.exist?(filepath)

        CSV.read(filepath, headers: true).filter_map do |row|
          parse_candle(row: row, symbol: symbol, from_time: from_time, to_time: to_time, timeframe: timeframe, candle_class: candle_class)
        end.sort_by(&:timestamp)
      end

      def parse_candle(row:, symbol:, from_time:, to_time:, timeframe:, candle_class:)
        timestamp = Time.parse(row['timestamp'])
        return nil if timestamp < from_time || timestamp > to_time

        candle_class.new(
          symbol: symbol,
          timestamp: timestamp,
          open: row['open'].to_f,
          high: row['high'].to_f,
          low: row['low'].to_f,
          close: row['close'].to_f,
          volume: row['volume'].to_i,
          timeframe: timeframe
        )
      end
    end
  end
end
