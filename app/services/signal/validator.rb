# frozen_string_literal: true

module Signal
  class Validator
    def validate(signal_data)
      confidence = signal_data[:confidence] || 0.0

      if confidence < 0.5
        { valid: false, reason: 'low confidence' }
      elsif confidence < 0.7
        { valid: true, reason: 'moderate confidence' }
      else
        { valid: true, reason: 'high confidence' }
      end
    end
  end
end
