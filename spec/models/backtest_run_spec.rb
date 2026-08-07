require 'rails_helper'

RSpec.describe BacktestRun, type: :model do
  it 'defaults to pending status' do
    expect(described_class.new.status).to eq('pending')
  end

  it 'rejects a status outside the known set' do
    run = build(:backtest_run, status: 'bogus')

    expect(run).not_to be_valid
    expect(run.errors[:status]).to be_present
  end

  it 'requires a symbol' do
    run = build(:backtest_run, symbol: nil)

    expect(run).not_to be_valid
  end

  describe '#completed?' do
    it 'is true only when status is completed' do
      expect(build(:backtest_run, :completed)).to be_completed
      expect(build(:backtest_run)).not_to be_completed
    end
  end

  describe '.recent_first' do
    it 'orders by created_at descending' do
      older = create(:backtest_run, created_at: 2.days.ago)
      newer = create(:backtest_run, created_at: 1.day.ago)

      expect(described_class.recent_first.to_a).to eq([newer, older])
    end
  end

  describe '#strategy_version' do
    it 'is optional' do
      run = build(:backtest_run, strategy_version: nil)
      expect(run).to be_valid
    end

    it 'can be pinned to a Strategies::Version' do
      version = create(:strategy_version)
      run = create(:backtest_run, strategy_version: version)

      expect(run.reload.strategy_version).to eq(version)
    end
  end
end
