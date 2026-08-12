# frozen_string_literal: true

module Adapters
  module Margin
    # Live DhanHQ margin-calculator adapter — the SPAN + exposure margin a naked
    # short option actually blocks, needed for selling since (unlike buying) the
    # premium paid/received is not the position's real capital requirement.
    class DhanMarginAdapter
      PRODUCT_TYPE = 'MARGIN' # carry-forward F&O short; this gem has no NRML constant
      CACHE_TTL = 2.minutes

      # @return [BigDecimal, nil] total margin blocked for `quantity` lots of this
      #   option at `price`, or nil if the calculator call fails.
      def margin_for(segment:, security_id:, quantity:, price:, transaction_type: 'SELL')
        cache_key = "dhan_margin:#{segment}:#{security_id}:#{quantity}:#{price}:#{transaction_type}"

        cached = Rails.cache.fetch(cache_key, expires_in: CACHE_TTL) do
          result = DhanHQ::Models::Margin.calculate(
            dhan_client_id: client_id,
            exchange_segment: segment,
            transaction_type: transaction_type,
            quantity: quantity,
            product_type: PRODUCT_TYPE,
            security_id: security_id.to_s,
            price: price.to_f
          )
          result.total_margin&.to_s
        end
        cached && BigDecimal(cached)
      rescue StandardError => e
        Rails.logger.error("[DhanMarginAdapter] margin_for failed for #{segment}-#{security_id}: #{e.class} - #{e.message}")
        nil
      end

      private

      def client_id
        ENV['DHAN_CLIENT_ID'].presence || ENV['CLIENT_ID'].presence
      end
    end
  end
end
