# frozen_string_literal: true

class PaperDailyWallet < ApplicationRecord
  validates :trading_date, presence: true, uniqueness: { scope: :mode, case_sensitive: true }
end
