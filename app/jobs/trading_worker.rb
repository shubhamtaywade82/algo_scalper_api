# frozen_string_literal: true

class TradingWorker < ApplicationJob
  queue_as :default

  def perform
    Trading::TradingService.new.execute_cycle!
  end
end
