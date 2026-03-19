# == Schema Information
#
# Table name: trade_telemetry
#
#  id                         :integer          not null, primary key
#  tracker_id                 :integer          not null
#  index_key                  :string           not null
#  entry_time                 :datetime         not null
#  exit_time                  :datetime         not null
#  entry_tf                   :string           not null
#  htf_tf                     :string           not null
#  bos_age_at_entry           :integer
#  retrace_pct                :decimal(6, 4)
#  pullback_candles           :integer
#  entry_distance_r           :decimal(8, 4)
#  continuation_body_position :decimal(6, 4)
#  time_from_bos_to_entry     :integer
#  max_r_reached              :decimal(10, 4)
#  exit_r                     :decimal(10, 4)
#  exit_path                  :string
#  pnl_rupees                 :decimal(12, 4)
#  trade_state_at_exit        :string
#  created_at                 :datetime         not null
#  updated_at                 :datetime         not null
#
# Indexes
#
#  index_trade_telemetry_on_entry_time  (entry_time)
#  index_trade_telemetry_on_index_key   (index_key)
#  index_trade_telemetry_on_tracker_id  (tracker_id) UNIQUE
#

# frozen_string_literal: true

class TradeTelemetry < ApplicationRecord
  self.table_name = 'trade_telemetry'

  belongs_to :tracker, class_name: 'PositionTracker', optional: false, inverse_of: :trade_telemetry
end
