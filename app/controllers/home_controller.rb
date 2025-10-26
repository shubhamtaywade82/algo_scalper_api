# frozen_string_literal: true

class HomeController < ApplicationController
  def index
    render inline: <<~ERB
      <!DOCTYPE html>
      <html>
      <head>
        <title>Algo Scalper API - Live Market Data</title>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <style>
          body { font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif; margin: 0; padding: 20px; background: #f5f5f5; }
          .container { max-width: 1200px; margin: 0 auto; }
          .header { background: white; padding: 20px; border-radius: 8px; margin-bottom: 20px; box-shadow: 0 2px 4px rgba(0,0,0,0.1); }
          .ticker-grid { display: grid; grid-template-columns: repeat(auto-fit, minmax(300px, 1fr)); gap: 20px; }
          .ticker-card { background: white; padding: 20px; border-radius: 8px; box-shadow: 0 2px 4px rgba(0,0,0,0.1); }
          .ticker-card h3 { margin: 0 0 10px 0; color: #333; }
          .ltp { font-size: 24px; font-weight: bold; color: #2c3e50; }
          .timestamp { color: #7f8c8d; font-size: 12px; }
          .status { padding: 4px 8px; border-radius: 4px; font-size: 12px; font-weight: bold; }
          .status.connected { background: #d4edda; color: #155724; }
          .status.disconnected { background: #f8d7da; color: #721c24; }
          .status.loading { background: #fff3cd; color: #856404; }

          /* Options Section Styles */
          .options-section { margin-top: 15px; padding-top: 15px; border-top: 1px solid #e9ecef; }
          .options-row { display: flex; gap: 10px; }
          .option-cell { flex: 1; text-align: center; }
          .option-label { font-size: 11px; font-weight: bold; color: #6c757d; margin-bottom: 5px; }
          .option-price { font-size: 16px; font-weight: bold; padding: 8px; border-radius: 4px; }
          .option-cell.call .option-price { background: #d1ecf1; color: #0c5460; }
          .option-cell.put .option-price { background: #f8d7da; color: #721c24; }
        </style>
      </head>
      <body>
        <div class="container">
          <div class="header">
            <h1>🚀 Algo Scalper API - Live Market Data</h1>
            <p>Real-time market data streaming via WebSocket</p>
            <div>
              Connection Status: <span data-controller="connection-status" data-connection-status-target="status" class="status loading">Connecting...</span>
            </div>
          </div>

          <div class="ticker-grid">
            <!-- NIFTY -->
            <div class="ticker-card" data-controller="ticker-display" data-ticker-display-segment-value="IDX_I" data-ticker-display-security-id-value="13">
              <h3>📈 NIFTY</h3>
              <div class="ltp" data-ticker-display-target="ltp">Loading...</div>
              <div class="timestamp" data-ticker-display-target="timestamp">-</div>

              <!-- ATM Options -->
              <div class="options-section">
                <div class="options-row">
                  <div class="option-cell call">
                    <div class="option-label">CALL</div>
                    <div class="option-price" data-ticker-display-target="callPrice">-</div>
                  </div>
                  <div class="option-cell put">
                    <div class="option-label">PUT</div>
                    <div class="option-price" data-ticker-display-target="putPrice">-</div>
                  </div>
                </div>
              </div>
            </div>

            <!-- BANKNIFTY -->
            <div class="ticker-card" data-controller="ticker-display" data-ticker-display-segment-value="IDX_I" data-ticker-display-security-id-value="25">
              <h3>🏦 BANKNIFTY</h3>
              <div class="ltp" data-ticker-display-target="ltp">Loading...</div>
              <div class="timestamp" data-ticker-display-target="timestamp">-</div>

              <!-- ATM Options -->
              <div class="options-section">
                <div class="options-row">
                  <div class="option-cell call">
                    <div class="option-label">CALL</div>
                    <div class="option-price" data-ticker-display-target="callPrice">-</div>
                  </div>
                  <div class="option-cell put">
                    <div class="option-label">PUT</div>
                    <div class="option-price" data-ticker-display-target="putPrice">-</div>
                  </div>
                </div>
              </div>
            </div>

            <!-- SENSEX -->
            <div class="ticker-card" data-controller="ticker-display" data-ticker-display-segment-value="IDX_I" data-ticker-display-security-id-value="51">
              <h3>📊 SENSEX</h3>
              <div class="ltp" data-ticker-display-target="ltp">Loading...</div>
              <div class="timestamp" data-ticker-display-target="timestamp">-</div>

              <!-- ATM Options -->
              <div class="options-section">
                <div class="options-row">
                  <div class="option-cell call">
                    <div class="option-label">CALL</div>
                    <div class="option-price" data-ticker-display-target="callPrice">-</div>
                  </div>
                  <div class="option-cell put">
                    <div class="option-label">PUT</div>
                    <div class="option-price" data-ticker-display-target="putPrice">-</div>
                  </div>
                </div>
              </div>
            </div>
          </div>
        </div>

        <script src="https://unpkg.com/@hotwired/stimulus/dist/stimulus.umd.js"></script>
        <script src="https://unpkg.com/@rails/actioncable/app/assets/javascripts/actioncable.js"></script>
        <script>
          console.log('Script loading...');

          class TickerDisplayController extends Stimulus.Controller {
            static targets = ["ltp", "timestamp", "callPrice", "putPrice"];
            static values = { segment: String, securityId: String };

            connect() {
              console.log(`TickerDisplay connected for ${this.segmentValue}:${this.securityIdValue}`);
              this.setupSubscription();
            }

            setupSubscription() {
              console.log('Setting up subscription...');

              if (!window.tickerCable) {
                console.log('Creating ActionCable consumer...');
                window.tickerCable = ActionCable.createConsumer("/cable");

                console.log('Creating subscription...');
                window.tickerSubscription = window.tickerCable.subscriptions.create({ channel: "TickerChannel" }, {
                  received: (data) => {
                    console.log('Received tick:', data);
                    // Update all ticker displays
                    window.updateAllTickers(data);
                  },
                  connected: () => {
                    console.log('WebSocket connected!');
                    window.updateAllConnectionStatus('connected');
                  },
                  disconnected: () => {
                    console.log('WebSocket disconnected!');
                    window.updateAllConnectionStatus('disconnected');
                  },
                  rejected: () => {
                    console.log('WebSocket connection rejected!');
                    window.updateAllConnectionStatus('disconnected');
                  }
                });
              }
            }

            handleTick(data) {
              console.log('Handling tick:', data);
              const key = `${data.segment}:${data.security_id}`;
              const expected = `${this.segmentValue}:${this.securityIdValue}`;

              console.log(`Comparing ${key} with ${expected}`);

              if (key === expected && data.ltp) {
                this.ltpTarget.textContent = Number(data.ltp).toFixed(2);
                this.timestampTarget.textContent = new Date().toLocaleTimeString();
                console.log(`Updated ${this.segmentValue}:${this.securityIdValue} = ${data.ltp}`);
              }

              // Handle option price updates
              this.handleOptionTick(data);
            }

            handleOptionTick(data) {
              // Check if this is an option tick for our index
              const indexKey = this.getIndexKey();
              if (!indexKey) return;

              // Get ATM option contracts for this index
              const atmOptions = window.atmOptions?.[indexKey];
              if (!atmOptions) return;

              // Check if this tick matches our ATM CALL option
              if (atmOptions.call &&
                  data.segment === atmOptions.call.segment &&
                  data.security_id === atmOptions.call.security_id) {
                if (this.hasCallPriceTarget) {
                  this.callPriceTarget.textContent = Number(data.ltp).toFixed(2);
                  console.log(`Updated ${indexKey} CALL: ${data.ltp}`);
                }
              }

              // Check if this tick matches our ATM PUT option
              if (atmOptions.put &&
                  data.segment === atmOptions.put.segment &&
                  data.security_id === atmOptions.put.security_id) {
                if (this.hasPutPriceTarget) {
                  this.putPriceTarget.textContent = Number(data.ltp).toFixed(2);
                  console.log(`Updated ${indexKey} PUT: ${data.ltp}`);
                }
              }
            }

            getIndexKey() {
              // Map security IDs to index keys
              const indexMap = {
                '13': 'NIFTY',
                '25': 'BANKNIFTY',
                '51': 'SENSEX'
              };
              return indexMap[this.securityIdValue];
            }

            updateConnectionStatus(status) {
              console.log('Updating connection status:', status);
              const statusElement = document.querySelector('[data-controller="connection-status"] [data-connection-status-target="status"]');
              if (statusElement) {
                statusElement.className = `status ${status}`;
                statusElement.textContent = status === 'connected' ? 'Connected' : 'Disconnected';
              }
            }
          }

          class ConnectionStatusController extends Stimulus.Controller {
            static targets = ["status"];

            connect() {
              console.log('ConnectionStatus controller connected');
            }
          }

          // Global ATM options data
          window.atmOptions = {};

          // Load ATM options data from server
          window.loadAtmOptions = async function() {
            try {
              const response = await fetch('/api/atm_options');
              if (response.ok) {
                window.atmOptions = await response.json();
                console.log('Loaded ATM options:', window.atmOptions);
              } else {
                console.warn('Failed to load ATM options:', response.status);
              }
            } catch (error) {
              console.error('Error loading ATM options:', error);
            }
          };

          // Global functions to handle all tickers
          window.updateAllTickers = function(data) {
            console.log('Updating all tickers with data:', data);
            const key = `${data.segment}:${data.security_id}`;

            // Find all ticker displays and update matching ones
            document.querySelectorAll('[data-controller="ticker-display"]').forEach(element => {
              const controller = window.Stimulus.getControllerForElementAndIdentifier(element, 'ticker-display');
              if (controller) {
                controller.handleTick(data);
              }
            });
          };

          window.updateAllConnectionStatus = function(status) {
            console.log('Updating all connection status to:', status);
            const statusElement = document.querySelector('[data-controller="connection-status"] [data-connection-status-target="status"]');
            if (statusElement) {
              statusElement.className = `status ${status}`;
              statusElement.textContent = status === 'connected' ? 'Connected' : 'Disconnected';
            }
          };

          // Initialize Stimulus
          console.log('Starting Stimulus...');
          window.Stimulus = Stimulus.Application.start();
          window.Stimulus.register("ticker-display", TickerDisplayController);
          window.Stimulus.register("connection-status", ConnectionStatusController);
          console.log('Stimulus started and controllers registered');

          // Load ATM options data
          window.loadAtmOptions();
        </script>
      </body>
      </html>
    ERB
  end
end
