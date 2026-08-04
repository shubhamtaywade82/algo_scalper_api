# frozen_string_literal: true

module Research
  # Converts a raw DhanHQ ExpiredOptionsData side-payload (parallel arrays
  # keyed by "timestamp"/"open"/.../"strike") into row hashes matching the
  # research_option_bars schema.
  class OptionBarNormalizer
    class << self
      def normalize(raw_side_data, symbol:, exchange_segment:, expiry_flag:, option_type:, strike_label:,
                     interval:, source: "rolling_option")
        return [] unless raw_side_data && raw_side_data["timestamp"]

        raw_side_data["timestamp"].each_with_index.map do |ts, i|
          {
            underlying_symbol: symbol.to_s.upcase,
            exchange_segment: exchange_segment,
            instrument: "OPTIDX",
            expiry_flag: expiry_flag,
            option_type: option_type.to_s.upcase,
            strike_label: strike_label,
            actual_strike: raw_side_data["strike"]&.[](i)&.to_f,
            interval: interval.to_s,
            ts: Time.at(ts).in_time_zone("Asia/Kolkata"),
            open: raw_side_data["open"][i].to_f,
            high: raw_side_data["high"][i].to_f,
            low: raw_side_data["low"][i].to_f,
            close: raw_side_data["close"][i].to_f,
            volume: raw_side_data["volume"][i].to_i,
            oi: raw_side_data["oi"]&.[](i)&.to_i,
            iv: raw_side_data["iv"]&.[](i)&.to_f,
            spot: raw_side_data["spot"]&.[](i)&.to_f,
            source: source
          }
        end
      end
    end
  end
end
