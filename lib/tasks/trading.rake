# frozen_string_literal: true

namespace :trading do
  desc 'Start trading system daemon (separate process)'
  task daemon: :environment do
    TradingSystem::Daemon.start
  end
end

