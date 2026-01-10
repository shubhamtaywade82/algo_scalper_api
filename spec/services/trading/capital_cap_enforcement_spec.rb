# frozen_string_literal: true

require 'rails_helper'

RSpec.describe '₹30,000 capital cap enforcement' do
  it 'never returns lots whose buy value exceeds ₹30,000' do
    premium = 250.0
    lot_size = 65
    permission_cap = 99

    lots = Trading::CapitalAllocator.max_lots(
      premium: premium,
      lot_size: lot_size,
      permission_cap: permission_cap
    )

    buy_value = lots * premium * lot_size
    expect(buy_value).to be <= 30_000.0
  end
end

