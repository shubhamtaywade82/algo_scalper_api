# frozen_string_literal: true

module Signal
  class CycleSummary
    attr_reader :index_key, :outcome, :block_code, :regime, :direction

    def initialize(index_key:)
      @index_key = index_key.to_s
      @outcome = :pending
      @block_code = nil
    end

    def skip!(code, regime: nil, direction: nil)
      assign!(:skipped, code, regime, direction)
    end

    def block!(code, regime: nil, direction: nil)
      assign!(:blocked, code, regime, direction)
    end

    def entered!(direction: nil, regime: nil)
      @outcome = :entered
      @block_code = nil
      @regime = regime&.to_s
      @direction = direction&.to_s
      self
    end

    def pending?
      @outcome == :pending
    end

    def finalize_pending!(code = 'no_setup')
      block!(code) if pending?

      self
    end

    def log_line
      parts = ["[SignalScheduler] #{index_key} cycle:", "outcome=#{outcome}"]
      parts << "regime=#{regime || 'n/a'}"
      parts << "direction=#{direction || 'n/a'}"
      parts << "block=#{block_code}" if block_code.present?
      parts.join(' ')
    end

    private

    def assign!(outcome, code, regime, direction)
      @outcome = outcome
      @block_code = code.to_s
      @regime = regime&.to_s
      @direction = direction&.to_s
      self
    end
  end
end
