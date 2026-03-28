# frozen_string_literal: true

module Execution
  class OrderRetry
    MAX_RETRIES = 3
    RETRY_DELAY = 0.5

    def self.call
      attempts = 0
      begin
        attempts += 1
        yield
      rescue StandardError => e
        raise e if attempts >= MAX_RETRIES
        sleep(RETRY_DELAY * attempts)
        retry
      end
    end
  end
end
