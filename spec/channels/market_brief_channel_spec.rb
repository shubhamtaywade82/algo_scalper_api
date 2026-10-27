# frozen_string_literal: true

require 'rails_helper'

RSpec.describe MarketBriefChannel do
  it 'streams the market brief frames' do
    subscribe
    expect(subscription).to be_confirmed
    expect(subscription).to have_stream_from('market_brief')
  end
end
