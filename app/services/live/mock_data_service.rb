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
        Rails.logger.info("[MockData] Starting mock data service")

        while @running
          begin
            # Mock data for the three indices
            mock_data = [
              { segment: "IDX_I", security_id: "13", ltp: 25200 + rand(200), name: "NIFTY" },
              { segment: "IDX_I", security_id: "25", ltp: 56500 + rand(300), name: "BANKNIFTY" },
              { segment: "IDX_I", security_id: "51", ltp: 82000 + rand(500), name: "SENSEX" }
            ]

            mock_data.each do |data|
              tick_data = {
                segment: data[:segment],
                security_id: data[:security_id],
                ltp: data[:ltp],
                kind: :quote,
                ts: Time.current.to_i
              }

              # Broadcast to TickerChannel
              TickerChannel.broadcast_to(TickerChannel::CHANNEL_ID, tick_data)
              Rails.logger.debug("[MockData] Broadcasted #{data[:name]}: #{data[:ltp]}")
            end

            sleep 2 # Update every 2 seconds
          rescue => e
            Rails.logger.error("[MockData] Error: #{e.message}")
            sleep 5
          end
        end
      end
    end

    def stop!
      @running = false
      @thread&.join
      Rails.logger.info("[MockData] Mock data service stopped")
    end

    def running?
      @running
    end
  end
end
