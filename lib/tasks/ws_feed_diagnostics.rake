# frozen_string_literal: true

namespace :ws do
  desc 'Check WebSocket market feed diagnostics'
  task diagnostics: :environment do
    load File.expand_path('ws_feed_diagnostics.rb', __dir__)
    WsFeedDiagnostics.run
  end
end

