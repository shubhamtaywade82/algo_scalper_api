# frozen_string_literal: true

require 'rails_helper'

RSpec.describe OptionChainChannel do
  it 'streams from the index-specific channel name' do
    subscribe(index_key: 'NIFTY')
    expect(subscription).to be_confirmed
    expect(subscription).to have_stream_from('option_chain_NIFTY')
  end

  it 'streams from a different index when a different index_key is given' do
    subscribe(index_key: 'BANKNIFTY')
    expect(subscription).to have_stream_from('option_chain_BANKNIFTY')
  end
end
