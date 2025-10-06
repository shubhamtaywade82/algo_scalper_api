# frozen_string_literal: true

class EquitiesIntradayJob < ApplicationJob
  queue_as :default

  def perform
    Equities::IntradayTradingService.new.execute!
  end
end
