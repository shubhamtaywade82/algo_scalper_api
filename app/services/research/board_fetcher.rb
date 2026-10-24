# frozen_string_literal: true

module Research
  # Fetches a full option "board" for a symbol/expiry/date window: every
  # strike from ATM-max_distance to ATM+max_distance, both CE and PE, so the
  # underlying and every nearby strike can be studied together for the same
  # session (Dhan's expired-options API supports up to ATM+/-10 near expiry).
  class BoardFetcher
    class << self
      # @return [Hash] { "CE" => { "ATM-2" => [Research::OptionBar, ...], ... }, "PE" => {...} }
      def call(symbol:, spot:, expiry_flag:, from_date:, to_date:, max_distance: 10, interval: "5")
        %w[CE PE].index_with do |option_type|
          fetch_strikes(symbol, option_type, expiry_flag, from_date, to_date, interval, spot, max_distance)
        end
      end

      private

      def fetch_strikes(symbol, option_type, expiry_flag, from_date, to_date, interval, spot, max_distance)
        Research::StrikeResolver
          .candidates(symbol: symbol, spot: spot, option_type: option_type, max_distance: max_distance)
          .to_h do |candidate|
          [candidate[:strike_label], Research::OptionCandleFetcher.call(
              symbol: symbol,
              option_type: option_type,
              expiry_flag: expiry_flag,
              strike_label: candidate[:strike_label],
              dhan_strike_param: candidate[:dhan_strike_param],
              from_date: from_date,
              to_date: to_date,
              interval: interval
            )]
        end
      end
    end
  end
end
