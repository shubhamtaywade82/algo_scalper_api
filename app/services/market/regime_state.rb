module Market
  class RegimeState
    MIN_STABILITY = 3
    COOLDOWN = 300 # seconds

    def initialize
      @current = nil
      @streak = 0
      @last_flip_at = nil
    end

    def update(new_regime)
      if new_regime == @current
        @streak += 1
      else
        @streak += 1

        if stable?(new_regime)
          @current = new_regime
          @last_flip_at = Time.now
          @streak = 0
        end
      end

      {
        regime: @current,
        stability: @streak,
        cooldown: cooldown_active?
      }
    end

    def cooldown_active?
      return false unless @last_flip_at
      Time.now - @last_flip_at < COOLDOWN
    end

    private

    def stable?(new_regime)
      @streak >= MIN_STABILITY
    end
  end
end
