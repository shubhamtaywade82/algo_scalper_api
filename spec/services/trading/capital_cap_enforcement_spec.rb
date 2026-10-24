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

  it 'refuses to size against an assumed ceiling when the config is missing' do
    # Error-handling review 2026-09 (wave 2): a missing target_rupees used to
    # silently size positions against a hardcoded ₹30,000 ceiling. (Test env
    # keeps the legacy ceiling for partial-stub specs — simulate production.)
    allow(AlgoConfig).to receive(:fetch).and_return({})
    allow(Rails).to receive(:env).and_return(ActiveSupport::StringInquirer.new('production'))

    expect { Trading::CapitalAllocator.max_capital_per_trade }
      .to raise_error(Errors::ConfigurationError, /target_rupees/)
  end
end
