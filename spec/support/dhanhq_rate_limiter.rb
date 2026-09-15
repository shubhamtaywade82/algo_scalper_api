# frozen_string_literal: true

# DhanHQ 3.4.0's RateLimiter throttles EVERY client request through shared
# per-API-type buckets — including VCR cassette replays, because the limiter
# runs inside DhanHQ::Client before the HTTP layer that VCR hooks into.
#
# Over a full-suite run this bites twice:
#
# - data_api calls accumulate toward the 7,000/day cap. Once the cap is hit,
#   RateLimiter#throttle! enters `loop { break if allow_request?; sleep(0.1) }`
#   and waits for the per-day cleanup thread — which sleeps 86,400s — so the
#   suite hangs until the CI job timeout. The mutex is held the whole time,
#   so every other request on the same API type queues behind it.
# - option_chain calls sleep up to 3s each (1-per-3s rule) inside the shared
#   mutex, dragging option-heavy spec files out by minutes to hours.
#
# Specs never want live throttling: VCR replays are instant and (correctly)
# unlimited. Neutralize the limiter for the whole suite. `shutdown` is a
# no-op as well — it joins cleanup threads that sleep for minutes/hours and
# die with the process anyway.
if defined?(DhanHQ::RateLimiter)
  module DhanhqTestRateLimiter
    def throttle!; end

    def shutdown; end
  end

  DhanHQ::RateLimiter.prepend(DhanhqTestRateLimiter)
end
