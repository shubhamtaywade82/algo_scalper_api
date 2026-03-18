module Analytics
  class LiveAdapter
    UPDATE_INTERVAL = 60 * 60 # 1 hour

    def initialize(trades:, last_updated_at: nil)
      @trades = trades
      @last_updated_at = last_updated_at
    end

    def call
      return nil unless should_update?

      rules = Analytics::AutoRuleEngine.new(@trades).call

      {
        rules: rules,
        updated_at: Time.now
      }
    end

    private

    def should_update?
      return true unless @last_updated_at

      Time.now - @last_updated_at >= UPDATE_INTERVAL
    end
  end
end
