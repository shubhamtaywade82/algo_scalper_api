# frozen_string_literal: true

require 'csv'

module Backtest
  # Loads historical tick data from CSV
  class DataLoader
    def initialize(path:)
      @path = path
    end

    def load
      return [] unless File.exist?(@path)

      rows = CSV.read(@path, headers: true)
      rows.map do |r|
        {
          timestamp: Time.parse(r['timestamp']),
          index_price: r['index_price'].to_f,
          option_price: r['option_price'].to_f,
          volume: r['volume'].to_i,
          oi: r['oi'].to_i
        }
      end
    end
  end
end
