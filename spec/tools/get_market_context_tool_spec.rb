# frozen_string_literal: true

require 'rails_helper'

RSpec.describe GetMarketContextTool do
  subject(:tool) { described_class.new }

  it 'is exposed to the model as get_market_context' do
    expect(tool.name).to eq('get_market_context')
  end

  it 'rejects arguments that do not match the execute signature' do
    expect(tool.call(symbol: 'NIFTY')).to include(error: /Invalid tool arguments/)
  end

  it 'returns a recoverable error for an unknown index' do
    allow(IndexConfigLoader).to receive(:load_indices).and_return([])
    expect(tool.call(index_key: 'nifty')).to eq(error: 'Unknown index: NIFTY')
  end
end
