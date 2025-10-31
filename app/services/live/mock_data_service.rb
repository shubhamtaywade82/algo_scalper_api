# frozen_string_literal: true

module Live
  class MockDataService
    include Singleton

    def initialize
      @running = false
      @thread = nil
    end

    def start!
      return if @running

      @running = true
      @thread = Thread.new do
        Rails.logger.info('[MockData] Starting mock data service')

        while @running
          begin
            # Mock data for the three indices
            mock_data = [
              { segment: 'IDX_I', security_id: '13', ltp: rand(25_200..25_399), name: 'NIFTY' },
              { segment: 'IDX_I', security_id: '25', ltp: rand(56_500..56_799), name: 'BANKNIFTY' },
              { segment: 'IDX_I', security_id: '51', ltp: rand(82_000..82_499), name: 'SENSEX' }
            ]

            mock_data.each do |data|
              tick_data = {
                segment: data[:segment],
                security_id: data[:security_id],
                ltp: data[:ltp],
                kind: :quote,
                ts: Time.current.to_i
              }

              # Populate TickCache (like real WebSocket does)
              Live::TickCache.put(tick_data)

              # Broadcast to TickerChannel
              TickerChannel.broadcast_to(TickerChannel::CHANNEL_ID, tick_data) if defined?(TickerChannel)
              Rails.logger.debug { "[MockData] Broadcasted #{data[:name]}: #{data[:ltp]}" }
            end

            sleep 2 # Update every 2 seconds
          rescue StandardError => e
            Rails.logger.error("[MockData] Error: #{e.message}")
            sleep 5
          end
        end
      end
    end

    def stop!
      @running = false
      @thread&.join
      Rails.logger.info('[MockData] Mock data service stopped')
    end

    def running?
      @running
    end
  end
end
