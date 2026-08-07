# frozen_string_literal: true

require 'rails_helper'

RSpec.describe BacktestRunJob do
  let(:run) { create(:backtest_run, symbol: 'NIFTY', days_back: 30, params: { stop_loss_pct: 0.35 }) }
  let(:summary) do
    { total_trades: 12, win_rate: 58.33, total_pnl: 9800.0, max_drawdown: 1500.0, trades: [{ pnl: 500.0 }] }
  end
  let(:engine) { instance_double(Backtest::OptionsBuyingBacktester, summary: summary) }

  before do
    allow(Backtest::OptionsBuyingBacktester).to receive(:call).and_return(engine)
  end

  it 'transitions pending -> running -> completed and persists the flat KPI columns + full results' do
    described_class.new.perform(run.id)

    run.reload
    expect(run.status).to eq('completed')
    expect(run.total_trades).to eq(12)
    expect(run.win_rate).to eq(58.33)
    expect(run.total_pnl).to eq(9800.0)
    expect(run.max_drawdown).to eq(1500.0)
    expect(run.results).to include('total_trades' => 12, 'trades' => [{ 'pnl' => 500.0 }])
    expect(run.started_at).to be_present
    expect(run.finished_at).to be_present
  end

  it 'calls the engine with the run parameters, symbolizing params and casting trading_type' do
    described_class.new.perform(run.id)

    expect(Backtest::OptionsBuyingBacktester).to have_received(:call).with(
      symbol: 'NIFTY', days_back: 30, params: { stop_loss_pct: 0.35 }, trading_type: :options, entry_interval: '5'
    )
  end

  it 'marks the run failed with the error message when the engine raises, instead of leaving it stuck running' do
    allow(Backtest::OptionsBuyingBacktester).to receive(:call).and_raise(RuntimeError, 'Instrument NIFTY not found')

    described_class.new.perform(run.id)

    run.reload
    expect(run.status).to eq('failed')
    expect(run.error_message).to eq('RuntimeError: Instrument NIFTY not found')
    expect(run.finished_at).to be_present
  end

  context 'when the run has a pinned strategy_version' do
    let(:strategy_version) { create(:strategy_version) }
    let(:run) { create(:backtest_run, symbol: 'NIFTY', days_back: 30, strategy_version: strategy_version) }
    let(:strategy_engine) { instance_double(Backtest::StrategyBacktester, summary: summary) }

    before do
      allow(Backtest::StrategyBacktester).to receive(:call).and_return(strategy_engine)
    end

    it 'dispatches to Backtest::StrategyBacktester instead of OptionsBuyingBacktester' do
      described_class.new.perform(run.id)

      expect(Backtest::StrategyBacktester).to have_received(:call).with(
        symbol: 'NIFTY', days_back: 30, strategy_version: strategy_version, trading_type: :options, entry_interval: '5'
      )
      expect(Backtest::OptionsBuyingBacktester).not_to have_received(:call)
      expect(run.reload.status).to eq('completed')
    end
  end
end
