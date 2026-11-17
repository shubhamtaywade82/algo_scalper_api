# frozen_string_literal: true

namespace :shadow do
  desc 'Compare a day\'s paper trades with the options-trading-agent journal (DATE=YYYY-MM-DD, AGENT_JOURNAL_DIR=path)'
  task compare: :environment do
    date = ENV['DATE'] ? Date.iso8601(ENV['DATE']) : Time.zone.today
    journal_dir = ENV.fetch('AGENT_JOURNAL_DIR') { Rails.root.join('../options-trading-agent/data/journal').to_s }
    result = Reports::ShadowCompare.new(date: date, journal_dir: journal_dir).call
    puts Reports::ShadowCompare.render(date, result)
  end
end
