# == Schema Information
#
# Table name: watchlist_items
#
#  id             :integer          not null, primary key
#  segment        :string           not null
#  security_id    :string           not null
#  kind           :integer
#  label          :string
#  active         :boolean          default(TRUE), not null
#  watchable_type :string
#  watchable_id   :integer
#  created_at     :datetime         not null
#  updated_at     :datetime         not null
#
# Indexes
#
#  index_watchlist_items_on_segment_and_security_id          (segment,security_id) UNIQUE
#  index_watchlist_items_on_watchable_type_and_watchable_id  (watchable_type,watchable_id)
#

# frozen_string_literal: true

require 'rails_helper'

RSpec.describe WatchlistItem do
  pending "add some examples to (or delete) #{__FILE__}"
end
