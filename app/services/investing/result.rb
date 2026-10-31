# frozen_string_literal: true

module Investing
  # Uniform service result for the Investing domain (TDD §6).
  # Domain failures are values, not exceptions: services return Result and
  # callers branch on success?/errors. Typed error entries are
  # [Symbol, Hash] pairs, e.g. [:weights_do_not_sum_to_100, { sum: 99.9999 }].
  Result = Struct.new(:ok, :payload, :errors, keyword_init: true) do
    def self.success(payload = {}) = new(ok: true, payload: payload, errors: [])
    def self.failure(errors) = new(ok: false, payload: nil, errors: Array(errors))

    def success? = ok
    def failure? = !ok
  end
end
