# frozen_string_literal: true

# ExecutionMode determines whether the system runs in paper trading mode
# or live trading mode based on the PAPER_MODE environment variable
module ExecutionMode
  def self.paper?
    ENV.fetch('PAPER_MODE', 'false') == 'true'
  end
end

