# == Schema Information
#
# Table name: settings
#
#  id         :integer          not null, primary key
#  key        :string           not null
#  value      :text
#  created_at :datetime         not null
#  updated_at :datetime         not null
#
# Indexes
#
#  index_settings_on_key  (key) UNIQUE
#

# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Setting do
  pending "add some examples to (or delete) #{__FILE__}"
end
