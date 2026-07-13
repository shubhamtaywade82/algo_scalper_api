# frozen_string_literal: true

require 'time'

module MarketData
  # Combines spot (index) candles with option candles based on timestamp
  class SpotOptionsCombiner
    def self.combine(spot_data:, call_data:, put_data:)
      # Convert call_data and put_data to Hash for O(1) lookup
      call_map = map_data_by_timestamp(call_data)
      put_map = map_data_by_timestamp(put_data)

      combined_dataset = []

      spot_data[:timestamp].each_with_index do |ts, i|
        # Dhan timestamps are often epoch integers
        key = ts.to_i

        row = {
          timestamp: Time.at(ts),
          spot_open: spot_data[:open][i],
          spot_high: spot_data[:high][i],
          spot_low: spot_data[:low][i],
          spot_close: spot_data[:close][i],
          spot_volume: spot_data[:volume][i]
        }

        # Add Call data if exists
        if call_map[key]
          row.merge!(
            ce_open: call_map[key][:open],
            ce_high: call_map[key][:high],
            ce_low: call_map[key][:low],
            ce_close: call_map[key][:close],
            ce_volume: call_map[key][:volume],
            ce_iv: call_map[key][:iv],
            ce_oi: call_map[key][:oi],
            ce_strike: call_map[key][:strike]
          )
        end

        # Add Put data if exists
        if put_map[key]
          row.merge!(
            pe_open: put_map[key][:open],
            pe_high: put_map[key][:high],
            pe_low: put_map[key][:low],
            pe_close: put_map[key][:close],
            pe_volume: put_map[key][:volume],
            pe_iv: put_map[key][:iv],
            pe_oi: put_map[key][:oi],
            pe_strike: put_map[key][:strike]
          )
        end

        combined_dataset << row if call_map[key] || put_map[key]
      end

      combined_dataset
    end

    private

    def self.map_data_by_timestamp(data)
      map = {}
      return map unless data && data[:timestamp]

      data[:timestamp].each_with_index do |ts, i|
        map[ts.to_i] = {
          open: data[:open][i],
          high: data[:high][i],
          low: data[:low][i],
          close: data[:close][i],
          volume: data[:volume][i],
          iv: data[:iv][i],
          oi: data[:oi][i],
          strike: data[:strike][i]
        }
      end
      map
    end
  end
end
