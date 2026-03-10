# frozen_string_literal: true

class InstitutionalMomentumStrategy
  attr_reader :series

  def initialize(series:)
    @series = series
    @symbol = series.symbol
    @filter = Entries::EntryFilterEngine.new(series: series, symbol: @symbol)
  end

  def generate_signal(index)
    return nil if index < 21

    # OPTIMIZED: Reuse the same series but tell the filter what the current "end" is
    if @filter.valid_entry_at?(index: index, direction: :bullish)
      return { type: :ce, confidence: 80 }
    elsif @filter.valid_entry_at?(index: index, direction: :bearish)
      return { type: :pe, confidence: 80 }
    end

    nil
  end
end
