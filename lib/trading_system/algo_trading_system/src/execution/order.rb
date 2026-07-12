# frozen_string_literal: true

module Execution
  Order = Struct.new(
    :order_id,
    :symbol,
    :exchange,
    :segment,
    :transaction_type,
    :order_type,
    :product_type,
    :quantity,
    :price,
    :trigger_price,
    :status,
    :filled_price,
    :filled_at,
    keyword_init: true
  )
end
