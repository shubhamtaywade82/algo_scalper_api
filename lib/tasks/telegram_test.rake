# frozen_string_literal: true

namespace :telegram do
  desc 'Test Telegram notifier - sends test notifications'
  task test: :environment do
    require_relative '../../scripts/test_telegram_notifier'
  end
end
