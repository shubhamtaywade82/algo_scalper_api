# frozen_string_literal: true

class Derivative < ApplicationRecord
  include InstrumentHelpers

  belongs_to :instrument
  has_many :watchlist_items, as: :watchable, dependent: :nullify, inverse_of: :watchable
  has_one  :watchlist_item,  -> { where(active: true) }, as: :watchable, class_name: "WatchlistItem"

  scope :options, -> { where.not(option_type: [ nil, "" ]) }
  scope :futures, -> { where(option_type: [ nil, "" ]) }
end
