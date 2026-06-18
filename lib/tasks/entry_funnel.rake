# frozen_string_literal: true

namespace :trading do
  desc <<~DESC.squish
    Entry funnel metrics: breakout arms, signal skips, guard blocks, and entries.
    DATE=YYYY-MM-DD (default today), INDEX=nifty|banknifty|sensex, JSON=1, LIVE=1 (Redis snapshot).
  DESC
  task entry_funnel: :environment do
    date = begin
      Date.parse(ENV.fetch('DATE', Time.zone.today.to_s))
    rescue ArgumentError
      Time.zone.today
    end
    index_key = ENV['INDEX']&.downcase
    include_live = ENV['LIVE'].to_s == '1'

    service = Observability::EntryFunnelMetrics.new(
      date: date,
      index_key: index_key,
      include_live_state: include_live
    )

    if ENV['JSON'].to_s == '1'
      puts JSON.pretty_generate(service.call)
    else
      puts service.render
    end
  end
end
