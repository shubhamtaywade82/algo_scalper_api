# frozen_string_literal: true

module Specifications
  # Specification for trading session validation
  class TradingSessionSpecification < BaseSpecification
    def satisfied?(context)
      session_check = TradingSession::Service.entry_allowed?
      session_check[:allowed] == true
    end

    def failure_reason(context)
      session_check = TradingSession::Service.entry_allowed?
      session_check[:reason] || 'Trading session not allowed'
    end
  end

  # Specification for daily limit validation
  class DailyLimitSpecification < BaseSpecification
    def initialize(index_key:)
      @index_key = index_key
    end

    def satisfied?(context)
      daily_limits = Live::DailyLimits.new
      limit_check = daily_limits.can_trade?(index_key: @index_key)
      limit_check[:allowed] == true
    end

    def failure_reason(context)
      daily_limits = Live::DailyLimits.new
      limit_check = daily_limits.can_trade?(index_key: @index_key)
      limit_check[:reason] || 'Daily limit exceeded'
    end
  end

  # Specification for exposure validation
  class ExposureSpecification < BaseSpecification
    def initialize(instrument:, side:, max_same_side:)
      @instrument = instrument
      @side = side
      @max_same_side = max_same_side.to_i
    end

    def satisfied?(context)
      return false if @max_same_side <= 0

      active_positions = PositionTracker.active.where(side: @side).where(
        "(instrument_id = ? OR (watchable_type = 'Derivative' AND watchable_id IN (SELECT id FROM derivatives WHERE instrument_id = ?)))",
        @instrument.id, @instrument.id
      )

      active_positions.count < @max_same_side
    end

    def failure_reason(context)
      active_positions = PositionTracker.active.where(side: @side).where(
        "(instrument_id = ? OR (watchable_type = 'Derivative' AND watchable_id IN (SELECT id FROM derivatives WHERE instrument_id = ?)))",
        @instrument.id, @instrument.id
      )

      "Exposure limit reached: #{active_positions.count} >= #{@max_same_side} (side: #{@side})"
    end
  end

  # Specification for cooldown validation
  class CooldownSpecification < BaseSpecification
    def initialize(symbol:, cooldown_seconds:)
      @symbol = symbol.to_s
      @cooldown_seconds = cooldown_seconds.to_i
    end

    def satisfied?(context)
      return true if @symbol.blank? || @cooldown_seconds <= 0

      last_entry = Rails.cache.read("reentry:#{@symbol}")
      return true if last_entry.blank?

      (Time.current - last_entry) >= @cooldown_seconds
    end

    def failure_reason(context)
      last_entry = Rails.cache.read("reentry:#{@symbol}")
      return nil if last_entry.blank?

      remaining = @cooldown_seconds - (Time.current - last_entry).to_i
      "Cooldown active: #{remaining} seconds remaining for #{@symbol}"
    end
  end

  # Specification for LTP validation
  class LtpSpecification < BaseSpecification
    def initialize(ltp:)
      @ltp = ltp
    end

    def satisfied?(context)
      @ltp.present? && @ltp.to_f.positive?
    end

    def failure_reason(context)
      "Invalid LTP: #{@ltp.inspect}"
    end
  end

  # Specification for expiry date validation
  class ExpirySpecification < BaseSpecification
    def initialize(expiry_date:, max_days: 7)
      @expiry_date = expiry_date
      @max_days = max_days
    end

    def satisfied?(context)
      return true unless @expiry_date # Allow if expiry not available

      days_to_expiry = (@expiry_date - Time.zone.today).to_i
      days_to_expiry <= @max_days && days_to_expiry >= 0
    end

    def failure_reason(context)
      return nil unless @expiry_date

      days_to_expiry = (@expiry_date - Time.zone.today).to_i
      "Expiry too far: #{days_to_expiry} days (max: #{@max_days})"
    end
  end

  # Composite specification for entry eligibility
  class EntryEligibilitySpecification < BaseSpecification
    def initialize(index_cfg:, pick:, direction:)
      @index_cfg = index_cfg
      @pick = pick
      @direction = direction
      @specifications = build_specifications
    end

    def satisfied?(context)
      @specifications.all? { |spec| spec.satisfied?(context) }
    end

    def failure_reason(context)
      failed_spec = @specifications.find { |spec| !spec.satisfied?(context) }
      failed_spec&.failure_reason(context)
    end

    # Get all failure reasons for debugging
    def all_failure_reasons(context)
      @specifications.filter_map { |spec| spec.failure_reason(context) }
    end

    private

    def build_specifications
      [
        TradingSessionSpecification.new,
        DailyLimitSpecification.new(index_key: @index_cfg[:key]),
        ExposureSpecification.new(
          instrument: resolve_instrument,
          side: @direction == :bullish ? 'long_ce' : 'long_pe',
          max_same_side: @index_cfg[:max_same_side] || 1
        ),
        CooldownSpecification.new(
          symbol: @pick[:symbol],
          cooldown_seconds: @index_cfg[:cooldown_sec] || 0
        ),
        LtpSpecification.new(ltp: @pick[:ltp]),
        ExpirySpecification.new(expiry_date: @pick[:expiry])
      ]
    end

    def resolve_instrument
      # Try to get instrument from pick if available
      return @pick[:instrument] if @pick[:instrument].is_a?(Instrument)

      # Fallback: find by index key
      Instrument.find_by(symbol_name: @index_cfg[:key]) || Instrument.find_by(security_id: @index_cfg[:sid])
    end
  end
end
