# frozen_string_literal: true

module Market
  class RegimeState
    MIN_STABILITY = 3
    COOLDOWN = 300 # seconds

    def initialize
      @current = nil
      @streak = 0
      @last_flip_at = nil
      @pending_regime = nil
      @pending_count = 0
    end

    def update(new_regime)
      if new_regime == @current
        @streak += 1
        @pending_regime = nil
        @pending_count = 0
      else
        if new_regime == @pending_regime
          @pending_count += 1
          if @pending_count >= MIN_STABILITY
            @current = new_regime
            @last_flip_at = Time.current
            @streak = MIN_STABILITY
            @pending_regime = nil
            @pending_count = 0
          else
            @streak = 0
          end
        else
          @pending_regime = new_regime
          @pending_count = 1
          @streak = 0
        end
      end

      {
        regime: @current,
        stability: @current ? @streak : 0,
        cooldown: cooldown_active?
      }
    end

    def cooldown_active?
      return false unless @last_flip_at
      Time.current - @last_flip_at < COOLDOWN
    end
  end
end
