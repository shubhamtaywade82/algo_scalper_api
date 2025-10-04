# frozen_string_literal: true

class Derivative < ApplicationRecord
  include InstrumentHelpers

  belongs_to :instrument

  scope :options, -> { where.not(option_type: [ nil, "" ]) }
  scope :futures, -> { where(option_type: [ nil, "" ]) }
end
