# == Schema Information
#
# Table name: dhan_access_tokens
#
#  id          :integer          not null, primary key
#  token       :string           not null
#  expiry_time :datetime         not null
#  created_at  :datetime         not null
#  updated_at  :datetime         not null
#
# Indexes
#
#  index_dhan_access_tokens_on_expiry_time  (expiry_time)
#

# frozen_string_literal: true

class DhanAccessToken < ApplicationRecord
  def expired?
    expiry_time <= Time.current
  end

  def expiring_soon?(buffer_minutes: 30)
    expiry_time <= buffer_minutes.minutes.from_now
  end
end

