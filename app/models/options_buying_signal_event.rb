# frozen_string_literal: true

class OptionsBuyingSignalEvent < ApplicationRecord
  self.table_name = 'options_buying_signal_events'

  validates :index_key, presence: true
  validates :event_type, presence: true
  validates :occurred_at, presence: true
  # metadata is jsonb NOT NULL DEFAULT {}; an empty hash is valid (`{}.present?` is
  # false, so a presence validation would reject the column's own default).
end
