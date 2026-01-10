# frozen_string_literal: true

namespace :test do
  desc 'Test WebSocket connection and LTP retrieval for subscribed instruments'
  task :ws, %i[instruments segment wait] => :environment do |_t, args|
    instruments = args[:instruments]
    segment = args[:segment] || 'IDX_I'
    wait_seconds = (args[:wait] || '15').to_i

    load File.expand_path('ws_connection_test.rb', __dir__)
    result = WsConnectionTest.run(
      instruments: instruments,
      segment: segment,
      wait_seconds: wait_seconds
    )

    exit(result[:success] ? 0 : 1)
  end
end
