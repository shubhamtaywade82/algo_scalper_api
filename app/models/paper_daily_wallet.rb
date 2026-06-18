# frozen_string_literal: true

class PaperDailyWallet < ApplicationRecord
  validates :trading_date, presence: true, uniqueness: { case_sensitive: true }
end
