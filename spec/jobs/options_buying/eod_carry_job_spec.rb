# frozen_string_literal: true

require 'rails_helper'

RSpec.describe OptionsBuying::EodCarryJob do
  before { allow(OptionsBuying::EodCarryManager).to receive(:run!) }

  it 'runs the carry manager when positional mode is active and the market is open' do
    allow(OptionsBuying::Mode).to receive(:positional_active?).and_return(true)
    allow(TradingSession::Service).to receive(:market_closed?).and_return(false)

    described_class.new.perform

    expect(OptionsBuying::EodCarryManager).to have_received(:run!)
  end

  it 'does nothing when positional mode is off' do
    allow(OptionsBuying::Mode).to receive(:positional_active?).and_return(false)

    described_class.new.perform

    expect(OptionsBuying::EodCarryManager).not_to have_received(:run!)
  end

  it 'does nothing when the market is closed' do
    allow(OptionsBuying::Mode).to receive(:positional_active?).and_return(true)
    allow(TradingSession::Service).to receive(:market_closed?).and_return(true)

    described_class.new.perform

    expect(OptionsBuying::EodCarryManager).not_to have_received(:run!)
  end
end
