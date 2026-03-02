# frozen_string_literal: true

class TradeTelemetry < ApplicationRecord
  self.table_name = 'trade_telemetry'

  belongs_to :tracker, class_name: 'PositionTracker'
end
