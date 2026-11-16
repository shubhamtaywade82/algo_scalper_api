# frozen_string_literal: true

class GetPositionDetailsTool < ApplicationMCPTool
  tool_name 'get_position_details'
  description 'Full detail for one position by tracker id: serialized row plus exit state (trailing stop, ' \
              'breakeven lock, secured stop, profit floor). Read-only.'

  property :position_id, type: 'integer', required: true, description: 'PositionTracker id'

  def perform
    tracker = PositionTracker.find_by(id: position_id)
    return render_json(error: "no position with id #{position_id}") if tracker.nil?

    row = Positions::Serializer.open(tracker).merge(exit_state(tracker))
    render_json(position_id: position_id, position: row)
  end

  private

  # Exit-engine state lives on tracker columns; reading them is safe because the
  # exit engine itself only runs inside the trading daemon.
  def exit_state(tracker)
    {
      trade_state: tracker.trade_state,
      breakeven_locked: tracker.breakeven_locked,
      be_set: tracker.be_set,
      trailing_stop_price: tracker.trailing_stop_price&.to_f,
      secured_sl_price: tracker.secured_sl_price&.to_f,
      secured_sl_rupees: tracker.secured_sl_rupees&.to_f,
      profit_floor_rupees: tracker.profit_floor_rupees&.to_f,
      profit_zone_state: tracker.profit_zone_state,
      high_water_mark_pnl: tracker.high_water_mark_pnl&.to_f
    }
  end
end
