# frozen_string_literal: true

class TradeTelemetry < ApplicationRecord
  belongs_to :tracker, class_name: 'PositionTracker'
end
