# frozen_string_literal: true

class HomeController < ActionController::API
  def index
    render inline: <<~ERB
      <div class="container" data-controller="ticker-display" data-ticker-display-segment-value="IDX_I" data-ticker-display-security-id-value="13">
        <h1>Live Index</h1>
        <div>
          LTP: <span data-ticker-display-target="ltp">Loading...</span>
          <small>at <span data-ticker-display-target="timestamp">-</span></small>
        </div>
      </div>
      <script type="module">
        import { Application } from "https://cdn.skypack.dev/@hotwired/stimulus";
        import consumer from "https://cdn.skypack.dev/@rails/actioncable";

        class TickerDisplayController {
          static targets = ["ltp", "timestamp"];
          static values = { segment: String, securityId: String };
          connect() {
            this.application = Application.start();
            // Wire ActionCable subscription
            this.cable = consumer.createConsumer("/cable");
            this.subscription = this.cable.subscriptions.create({ channel: "TickerChannel" }, {
              received: (data) => this.handleTick(data)
            });
          }
          handleTick(data) {
            const key = `${data.segment}:${data.security_id}`;
            const expected = `${this.segmentValue}:${this.securityIdValue}`;
            if (key === expected && data.ltp) {
              this.ltpTarget.textContent = Number(data.ltp).toFixed(2);
              this.timestampTarget.textContent = new Date().toLocaleTimeString();
            }
          }
        }

        window.Stimulus = Application.start();
        window.Stimulus.register("ticker-display", TickerDisplayController);
      </script>
    ERB
  end
end
