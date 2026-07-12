# frozen_string_literal: true

module Research
  # Expands a Research::Signal into candidate strikes (ATM, ATM+/-N) across
  # the requested expiries, using the signal's own direction to pick CE vs PE.
  class CandidateBuilder
    class << self
      def build(signal:, expiry_flags: ["WEEK"], max_distance: 2, entry_model: "next_candle_open")
        option_type = option_type_for(signal.direction)
        return [] unless option_type

        Array(expiry_flags).flat_map do |expiry_flag|
          Research::StrikeResolver
            .candidates(symbol: signal.underlying_symbol, spot: signal.spot_price, option_type: option_type,
                        max_distance: max_distance)
            .map { |candidate| find_or_create(signal, expiry_flag, option_type, entry_model, candidate) }
        end
      end

      private

      def option_type_for(direction)
        case direction.to_s
        when "bullish" then "CE"
        when "bearish" then "PE"
        end
      end

      def find_or_create(signal, expiry_flag, option_type, entry_model, candidate)
        Research::OptionCandidate.find_or_create_by!(
          research_signal: signal,
          expiry_flag: expiry_flag,
          option_type: option_type,
          strike_distance: candidate[:distance],
          entry_model: entry_model
        ) do |record|
          record.underlying_symbol = signal.underlying_symbol
          record.strike_label = candidate[:strike_label]
          record.actual_strike = candidate[:actual_strike]
          record.metadata = { "dhan_strike_param" => candidate[:dhan_strike_param] }
        end
      end
    end
  end
end
