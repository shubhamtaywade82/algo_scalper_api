# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Candles::DailyBackfillJob do
  it 'enqueues Candles::BackfillJob for NIFTY, BANKNIFTY, and SENSEX' do
    expect(Candles::BackfillJob).to receive(:perform_later).with(security_id: '13')
    expect(Candles::BackfillJob).to receive(:perform_later).with(security_id: '25')
    expect(Candles::BackfillJob).to receive(:perform_later).with(security_id: '51')

    described_class.perform_now
  end
end
