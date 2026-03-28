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

require 'rails_helper'

RSpec.describe Models::DhanAccessToken do
  pending "add some examples to (or delete) #{__FILE__}"
end
