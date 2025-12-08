# frozen_string_literal: true

module Builders
  # Builder for constructing bracket orders
  # Provides fluent API for configuring SL/TP and trailing stops
  class BracketOrderBuilder
    def initialize(tracker)
      @tracker = tracker
      @sl_price = nil
      @tp_price = nil
      @trailing_config = nil
      @reason = nil
      @validate = true
    end

    # Set stop loss price
    # @param price [BigDecimal, Float] Stop loss price
    # @return [self]
    def with_stop_loss(price)
      @sl_price = BigDecimal(price.to_s)
      self
    end

    # Set take profit price
    # @param price [BigDecimal, Float] Take profit price
    # @return [self]
    def with_take_profit(price)
      @tp_price = BigDecimal(price.to_s)
      self
    end

    # Calculate stop loss as percentage below entry
    # @param percentage [Float] Percentage (e.g., 0.30 for 30%)
    # @return [self]
    def with_stop_loss_percentage(percentage)
      entry_price = @tracker.entry_price.to_f
      raise ArgumentError, 'Tracker must have entry price' unless entry_price.positive?

      @sl_price = BigDecimal((entry_price * (1 - percentage)).to_s)
      self
    end

    # Calculate take profit as percentage above entry
    # @param percentage [Float] Percentage (e.g., 0.60 for 60%)
    # @return [self]
    def with_take_profit_percentage(percentage)
      entry_price = @tracker.entry_price.to_f
      raise ArgumentError, 'Tracker must have entry price' unless entry_price.positive?

      @tp_price = BigDecimal((entry_price * (1 + percentage)).to_s)
      self
    end

    # Set trailing stop configuration
    # @param config [Hash] Trailing config with :enabled, :activation_pct, :trail_pct
    # @return [self]
    def with_trailing(config)
      @trailing_config = {
        enabled: config[:enabled] || false,
        activation_pct: config[:activation_pct] || 0.20,
        trail_pct: config[:trail_pct] || 0.10
      }
      self
    end

    # Set reason for bracket placement
    # @param reason [String] Reason description
    # @return [self]
    def with_reason(reason)
      @reason = reason.to_s
      self
    end

    # Disable validation (use with caution)
    # @return [self]
    def without_validation
      @validate = false
      self
    end

    # Build and place the bracket order
    # @return [Hash] Result hash with :success, :sl_price, :tp_price, :error
    def build
      validate_builder if @validate

      # Use default SL/TP if not set
      calculate_defaults if @sl_price.nil? || @tp_price.nil?

      # Place bracket order
      Orders::BracketPlacer.place_bracket(
        tracker: @tracker,
        sl_price: @sl_price.to_f,
        tp_price: @tp_price.to_f,
        reason: @reason || 'builder_created'
      )
    rescue StandardError => e
      Rails.logger.error("[Builders::BracketOrderBuilder] Build failed: #{e.class} - #{e.message}")
      { success: false, error: e.message }
    end

    # Build bracket order configuration without placing
    # @return [Hash] Configuration hash
    def build_config
      calculate_defaults if @sl_price.nil? || @tp_price.nil?

      {
        tracker: @tracker,
        sl_price: @sl_price.to_f,
        tp_price: @tp_price.to_f,
        trailing_config: @trailing_config,
        reason: @reason
      }
    end

    private

    def validate_builder
      raise ArgumentError, 'Tracker is required' unless @tracker
      raise ArgumentError, 'Tracker must be active' unless @tracker.active?

      entry_price = @tracker.entry_price.to_f
      raise ArgumentError, 'Tracker must have entry price' unless entry_price.positive?

      if @sl_price && @sl_price.to_f >= entry_price
        raise ArgumentError, "Stop loss (#{@sl_price}) must be below entry price (#{entry_price})"
      end

      if @tp_price && @tp_price.to_f <= entry_price
        raise ArgumentError, "Take profit (#{@tp_price}) must be above entry price (#{entry_price})"
      end
    end

    def calculate_defaults
      entry_price = @tracker.entry_price.to_f
      return unless entry_price.positive?

      risk_cfg = AlgoConfig.fetch.dig(:risk) || {}
      sl_pct = risk_cfg[:sl_pct] || 0.30
      tp_pct = risk_cfg[:tp_pct] || 0.60

      @sl_price ||= BigDecimal((entry_price * (1 - sl_pct)).to_s)
      @tp_price ||= BigDecimal((entry_price * (1 + tp_pct)).to_s)
    end
  end
end
