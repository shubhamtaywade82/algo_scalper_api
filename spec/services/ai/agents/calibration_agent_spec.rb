# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Ai::Agents::CalibrationAgent do
  subject(:agent) { described_class.new }

  it 'recommends running calibration once the new-trade threshold is met' do
    5.times do
      tracker = create(:position_tracker, :exited)
      create(:trade_analytic, position_tracker: tracker, symbol: 'NIFTY')
    end

    result = agent.run(symbol: 'NIFTY', trigger_trades: 5)

    expect(result[:output][:should_run_calibration]).to be true
    expect(result[:output][:new_trades_since_last_run]).to eq(5)
  end

  it 'does not recommend running calibration below the threshold' do
    tracker = create(:position_tracker, :exited)
    create(:trade_analytic, position_tracker: tracker, symbol: 'NIFTY')

    result = agent.run(symbol: 'NIFTY', trigger_trades: 5)

    expect(result[:output][:should_run_calibration]).to be false
  end

  it 'never triggers Ai::Calibration::Runner unless auto_run is explicitly true' do
    allow(Ai::Calibration::Runner).to receive(:call)

    5.times do
      tracker = create(:position_tracker, :exited)
      create(:trade_analytic, position_tracker: tracker, symbol: 'NIFTY')
    end

    agent.run(symbol: 'NIFTY', trigger_trades: 5)

    expect(Ai::Calibration::Runner).not_to have_received(:call)
  end

  it 'delegates to Ai::Calibration::Runner when auto_run is true and threshold is met, ' \
     'but the resulting CalibrationRun still requires a human apply!' do
    run = build_stubbed(:calibration_run, symbol: 'NIFTY')
    allow(Ai::Calibration::Runner).to receive(:call).with(symbol: 'NIFTY', days: 30).and_return(run)

    5.times do
      tracker = create(:position_tracker, :exited)
      create(:trade_analytic, position_tracker: tracker, symbol: 'NIFTY')
    end

    result = agent.run(symbol: 'NIFTY', trigger_trades: 5, auto_run: true)

    expect(result[:output][:auto_run_triggered]).to be true
    expect(run.applied_at).to be_nil
  end

  it 'only counts trades created since the last CalibrationRun' do
    create(:calibration_run, symbol: 'NIFTY', created_at: 1.hour.ago)

    old_tracker = create(:position_tracker, :exited)
    create(:trade_analytic, position_tracker: old_tracker, symbol: 'NIFTY', created_at: 2.hours.ago)

    new_tracker = create(:position_tracker, :exited)
    create(:trade_analytic, position_tracker: new_tracker, symbol: 'NIFTY', created_at: 10.minutes.ago)

    result = agent.run(symbol: 'NIFTY', trigger_trades: 1)

    expect(result[:output][:new_trades_since_last_run]).to eq(1)
  end
end
