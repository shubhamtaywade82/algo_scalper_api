# frozen_string_literal: true

# == Schema Information
#
# Table name: candles
#
#  id               :bigint           not null, primary key
#  instrument_key   :string           not null
#  exchange_segment :string           not null
#  security_id      :string           not null
#  timeframe        :string           not null, default("1m")
#  ts               :datetime         not null
#  open             :decimal(12, 4)   not null
#  high             :decimal(12, 4)   not null
#  low              :decimal(12, 4)   not null
#  close            :decimal(12, 4)   not null
#  volume           :bigint           default(0)
#  oi               :bigint
#  source           :string           not null, default("live")
#  created_at       :datetime         not null
#  updated_at       :datetime         not null
#
# Indexes
#
#  index_candles_on_key_timeframe_ts       (instrument_key,timeframe,ts) UNIQUE
#  index_candles_on_security_timeframe_ts  (security_id,timeframe,ts)
#

module Candles
  class Record < ApplicationRecord
    self.table_name = "candles"

    validates :instrument_key, :exchange_segment, :security_id, :timeframe, :ts, presence: true
    validates :open, :high, :low, :close, presence: true
    validates :instrument_key, uniqueness: { scope: %i[timeframe ts] }

    scope :for_instrument, ->(key) { where(instrument_key: key.to_s) }
    scope :for_timeframe, ->(tf) { where(timeframe: tf.to_s) }
    scope :between, ->(from, to) { where(ts: from..to) }
  end
end
