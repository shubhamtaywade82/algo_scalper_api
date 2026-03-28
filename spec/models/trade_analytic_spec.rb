# == Schema Information
#
# Table name: trade_analytics
#
#  id                      :integer          not null, primary key
#  position_tracker_id     :integer          not null
#  symbol                  :string
#  entry_price             :decimal(, )
#  exit_price              :decimal(, )
#  max_favorable_excursion :decimal(, )
#  max_adverse_excursion   :decimal(, )
#  duration_seconds        :integer
#  volatility              :decimal(, )
#  strategy                :string
#  exit_reason             :string
#  created_at              :datetime         not null
#  updated_at              :datetime         not null
#
# Indexes
#
#  index_trade_analytics_on_position_tracker_id  (position_tracker_id)
#

# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Models::TradeAnalytic do
  pending "add some examples to (or delete) #{__FILE__}"
end
