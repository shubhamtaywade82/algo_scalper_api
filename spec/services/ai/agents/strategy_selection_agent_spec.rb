# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Ai::Agents::StrategySelectionAgent do
  subject(:agent) { described_class.new }

  it 'ranks strategies with enough sample trades by average pnl, best first' do
    create_list(:trade_memory, 5, strategy_name: 'strong_strategy', pnl_rupees: 1000, symbol: 'NIFTY')
    create_list(:trade_memory, 5, strategy_name: 'weak_strategy', pnl_rupees: -200, symbol: 'NIFTY')

    result = agent.run(index_key: 'NIFTY', min_trades: 5)

    expect(result[:output][:recommended_strategy]).to eq('strong_strategy')
    expect(result[:output][:ranked_strategies].pluck(:strategy)).to eq(%w[strong_strategy weak_strategy])
  end

  it 'excludes strategies below the minimum trade sample size' do
    create_list(:trade_memory, 2, strategy_name: 'thin_sample', pnl_rupees: 5000, symbol: 'NIFTY')

    result = agent.run(index_key: 'NIFTY', min_trades: 5)

    expect(result[:output][:ranked_strategies]).to be_empty
    expect(result[:confidence]).to eq(0.0)
  end

  it 'scopes to the given index_key' do
    create_list(:trade_memory, 5, strategy_name: 'nifty_strategy', symbol: 'NIFTY', pnl_rupees: 100)
    create_list(:trade_memory, 5, strategy_name: 'banknifty_strategy', symbol: 'BANKNIFTY', pnl_rupees: 100)

    result = agent.run(index_key: 'NIFTY', min_trades: 5)

    expect(result[:output][:ranked_strategies].pluck(:strategy)).to eq(['nifty_strategy'])
  end

  it 'never mutates the live regime-to-strategy mapping — it only returns a recommendation' do
    create_list(:trade_memory, 5, strategy_name: 'x', pnl_rupees: 100)
    expect { agent.run }.not_to change(AlgoConfig, :fetch)
  end
end
