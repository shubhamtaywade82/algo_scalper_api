# frozen_string_literal: true

class PositionTracker < ApplicationRecord
  module Broadcastable
    extend ActiveSupport::Concern

    def broadcast_position_activated
      ActionCable.server.broadcast("dashboard", {
        type: "position_activated",
        position: {
          id: id,
          symbol: symbol,
          side: side,
          quantity: quantity.to_i,
          entry_price: entry_price.to_f,
          index_key: index_key || meta&.dig('index_key'),
          direction: direction || meta&.dig('direction'),
          segment: segment,
          paper: paper?,
          created_at: created_at&.iso8601
        }
      })

      ActionCable.server.broadcast("holdings", { type: "holdings_changed", timestamp: Time.current.iso8601 })
      ActionCable.server.broadcast("funds", { type: "funds_changed", timestamp: Time.current.iso8601 })
    rescue StandardError => e
      Rails.logger.debug("[PositionTracker] broadcast_position_activated failed: #{e.message}")
    end

    def broadcast_position_exited
      ActionCable.server.broadcast("dashboard", {
        type: "position_exited",
        position: {
          id: id,
          symbol: symbol,
          side: side,
          quantity: quantity.to_i,
          entry_price: entry_price.to_f,
          exit_price: exit_price.to_f,
          pnl: last_pnl_rupees.to_f.round(2),
          pnl_pct: (last_pnl_pct.to_f * 100).round(2),
          exit_reason: exit_reason || meta&.dig('exit_reason'),
          index_key: index_key || meta&.dig('index_key'),
          paper: paper?,
          exited_at: exited_at&.iso8601
        }
      })

      ActionCable.server.broadcast("positions", {
        type: "position_exited",
        id: id
      })

      ActionCable.server.broadcast("holdings", { type: "holdings_changed", timestamp: Time.current.iso8601 })
      ActionCable.server.broadcast("funds", { type: "funds_changed", timestamp: Time.current.iso8601 })
    rescue StandardError => e
      Rails.logger.debug("[PositionTracker] broadcast_position_exited failed: #{e.message}")
    end
  end
end
