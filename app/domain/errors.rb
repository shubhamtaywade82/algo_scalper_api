# frozen_string_literal: true

# Domain error taxonomy for explicit failure states.
#
# Repository invariant (error-handling review 2026-09):
#   A method may return nil / false / 0 / an empty collection only when that is
#   a DOCUMENTED domain outcome. It may never use them as a substitute for
#   "missing", "malformed", "stale" or "unavailable" required information —
#   those states must become one of the typed errors below (or a deterministic
#   Result object at service boundaries).
#
# Mapping to failure semantics:
#
#   Errors::ConfigurationError    config document/setting missing, unreadable or corrupt
#   Errors::InvalidInstrument     instrument row violates domain invariants
#   Errors::InstrumentNotFound    broker identity / contract identity could not be resolved
#   Errors::InvalidMarketData     market data malformed (bad candle, unparseable tick field)
#   Errors::StaleMarketData       market data present but too old to trade on
#   Errors::InvalidQuantity       order quantity missing, non-integer, zero or negative
#   Errors::InvalidPrice          price missing/malformed where a valid price is mandatory
#   Errors::RiskViolation         a risk gate blocked the action (deterministic rejection)
#   Errors::ExecutionRejected     the execution layer refused the command
#   Errors::LedgerFailure         double-entry posting failed after retries/inspection
#   Errors::InvariantViolation    two sources that must agree disagree (data corruption)
#   Errors::InvalidParameter      a query/command argument is malformed
module Errors
  class Error < StandardError
    def initialize(message = nil)
      super
    end
  end

  # Configuration document/setting is missing, unreadable or corrupt.
  # Distinct from a legitimate "disabled" flag: NOT knowing is NOT "off".
  class ConfigurationError < Error; end

  # An instrument row violates a domain invariant (bad type composition etc.).
  class InvalidInstrument < Error; end

  # Broker identity (exchange+segment+security_id) or contract identity
  # (underlying+expiry+strike+option_type) could not be resolved.
  # Carries the query so log lines are actionable.
  class InstrumentNotFound < Error
    attr_reader :query

    def initialize(query = nil, message = nil)
      @query = query
      super(message || "instrument not found for #{query.inspect}")
    end
  end

  # Market data is present but malformed (unparseable numbers, missing fields).
  class InvalidMarketData < Error; end

  # Market data is well-formed but too old to act on.
  class StaleMarketData < Error; end

  # Order quantity is missing, non-integer, zero or negative.
  # Zero is a meaningful financial value; it is never a fallback.
  class InvalidQuantity < Error; end

  # A mandatory price is missing or malformed.
  class InvalidPrice < Error; end

  # A risk gate deterministically blocked the action.
  class RiskViolation < Error; end

  # The execution layer refused a command (pre-trade validation).
  class ExecutionRejected < Error; end

  # A double-entry posting failed and requires inspection/reconciliation.
  class LedgerFailure < Error; end

  # Two sources that must agree disagree — the row is corrupt, do not trade on it.
  class InvariantViolation < Error; end

  # A query/command argument is malformed (e.g. unparseable date).
  class InvalidParameter < Error; end
end
