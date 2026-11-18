# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'GET /api/reports/performance' do # rubocop:disable RSpec/DescribeClass
  let(:day_one) { Time.zone.local(2026, 11, 10, 11, 0) }
  let(:day_two) { Time.zone.local(2026, 11, 11, 11, 0) }

  def exited_trade(at:, pnl:)
    create(:position_tracker, status: 'exited', exited_at: at, last_pnl_rupees: pnl)
  end

  def summary
    response.parsed_body.fetch('summary')
  end

  context 'with a mix of winning, losing and flat trades' do
    before do
      exited_trade(at: day_one, pnl: 1000)
      exited_trade(at: day_one, pnl: -300)
      exited_trade(at: day_two, pnl: 500)
      exited_trade(at: day_two, pnl: 0)
      exited_trade(at: day_two, pnl: 500)
    end

    it 'summarises wins, losses and payoff figures' do
      get '/api/reports/performance'

      expect(response).to have_http_status(:ok)
      expect(summary).to include(
        'total_trades' => 5, 'wins' => 3, 'losses' => 2, 'win_rate_percent' => 60.0,
        'net_pnl' => 1700.0, 'avg_win' => 666.67, 'avg_loss' => -150.0,
        'max_win' => 1000.0, 'max_loss' => -300.0, 'expectancy' => 340.0
      )
    end

    it 'computes profit factor from gross profit over gross loss, not from the payoff ratio' do
      get '/api/reports/performance'

      # 2000 gross profit / 300 gross loss. The payoff ratio (666.67 / 150 = 4.44) would overstate it the other way.
      expect(summary['profit_factor']).to eq(6.67)
    end

    it 'returns a per-day pnl series in date order' do
      get '/api/reports/performance'

      expect(response.parsed_body.fetch('daily')).to eq(
        [{ 'date' => '2026-11-10', 'pnl' => 700.0 }, { 'date' => '2026-11-11', 'pnl' => 1000.0 }]
      )
    end

    it 'honours the since filter' do
      get '/api/reports/performance', params: { since: '2026-11-11' }

      expect(summary).to include('total_trades' => 3, 'net_pnl' => 1000.0)
    end
  end

  it 'returns zeros rather than dividing by zero when there are no trades' do
    get '/api/reports/performance'

    expect(summary).to include('total_trades' => 0, 'win_rate_percent' => 0.0, 'avg_win' => 0.0,
                               'avg_loss' => 0.0, 'profit_factor' => 0.0, 'expectancy' => 0.0)
    expect(response.parsed_body.fetch('daily')).to eq([])
  end
end
