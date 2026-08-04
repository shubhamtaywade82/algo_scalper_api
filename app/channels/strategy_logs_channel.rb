# frozen_string_literal: true

# Streams live strategy log lines per slug.
#
# Subscribe: `StrategyLogsChannel` with `{slug: "supertrend_v1"}`
# Broadcast: `ActionCable.server.broadcast("strategy_logs_supertrend_v1", {ts:, level:, line:})`
class StrategyLogsChannel < ApplicationCable::Channel
  def subscribed
    slug = params[:slug].to_s
    reject && return if slug.blank?

    stream_from "strategy_logs_#{slug}"
  end
end
