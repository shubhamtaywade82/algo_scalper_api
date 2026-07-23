# frozen_string_literal: true

module Indicators
  class VolumeProfile < ApplicationService
    DEFAULT_BIN_SIZE = 5.0
    HVN_THRESHOLD = 0.70
    LVN_THRESHOLD = 0.20

    attr_reader :candles, :bin_size

    def initialize(candles, bin_size: DEFAULT_BIN_SIZE)
      @candles = candles
      @bin_size = bin_size.to_f
    end

    def call
      histogram = Hash.new(0.0)

      candles.each do |c|
        vol = c[:volume].to_f
        next if vol <= 0

        high = c[:high].to_f
        low = c[:low].to_f

        if (high - low).abs < 0.01
          bin = ((low / bin_size).floor * bin_size).round(2)
          histogram[bin] += vol
          next
        end

        bin_count = [(high - low) / bin_size, 1].max.ceil
        vol_per_bin = vol / bin_count

        bin_count.times do |i|
          price = low + (i * bin_size)
          bin = ((price / bin_size).floor * bin_size).round(2)
          histogram[bin] += vol_per_bin
        end
      end

      return empty_result if histogram.empty?

      poc_bin = histogram.max_by { |_k, v| v }&.first
      max_vol = histogram[poc_bin] || 0.0

      hvns = []
      lvns = []

      histogram.sort.each do |price_bin, vol|
        hvns << price_bin if vol >= max_vol * HVN_THRESHOLD
        lvns << price_bin if vol <= max_vol * LVN_THRESHOLD && vol.positive?
      end

      {
        poc: poc_bin,
        hvns: hvns.sort,
        lvns: lvns.sort,
        max_volume: max_vol.round(2),
        total_volume: histogram.values.sum.round(2),
        bin_size: bin_size,
        histogram: histogram.sort_by { |k, _v| k }.to_h
      }
    end

    private

    def empty_result
      {
        poc: nil,
        hvns: [],
        lvns: [],
        max_volume: 0,
        total_volume: 0,
        bin_size: bin_size,
        histogram: {}
      }
    end
  end
end
