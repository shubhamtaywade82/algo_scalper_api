# frozen_string_literal: true

class PaperWallet < ApplicationRecord
  validates :initial_capital, :available_capital, :invested_capital, :total_pnl, presence: true

  def self.wallet
    first_or_create!(
      initial_capital: default_initial_capital,
      available_capital: default_initial_capital,
      invested_capital: 0,
      total_pnl: 0,
      mode: 'paper'
    )
  end

  def self.default_initial_capital
    raw = begin
      Rails.application.config_for(:algo).dig('paper_trading', 'initial_capital')
    rescue StandardError
      nil
    end
    BigDecimal((raw || 100_000).to_s)
  end

  def allocate!(amount)
    amt = BigDecimal(amount.to_s)
    raise ArgumentError, 'amount must be positive' if amt <= 0
    raise StandardError, 'insufficient capital' if available_capital < amt

    update!(available_capital: available_capital - amt, invested_capital: invested_capital + amt)
  end

  def release!(amount)
    amt = BigDecimal(amount.to_s)
    raise ArgumentError, 'amount must be positive' if amt <= 0

    update!(available_capital: available_capital + amt, invested_capital: [invested_capital - amt, 0].max)
  end

  def book_pnl!(pnl_amount)
    amt = BigDecimal(pnl_amount.to_s)
    update!(total_pnl: total_pnl + amt, available_capital: available_capital + amt)
  end
end
