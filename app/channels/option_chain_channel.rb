# frozen_string_literal: true

# Streams live option-chain snapshots (spot, ATM±5 legs with LTP/OI/IV/greeks) per index.
# Broadcasts:
#   { index_key:, spot:, atm_strike:, expiry:, legs: [...], chain_stale:, updated_at: }
# Fed by Options::ChainWatchService running in the trading daemon (see docs/superpowers/specs/2026-07-04-option-chain-scalper-view-design.md).
class OptionChainChannel < ApplicationCable::Channel
  def subscribed
    index_key = params[:index_key].to_s.upcase
    stream_from "option_chain_#{index_key}"
  end
end
