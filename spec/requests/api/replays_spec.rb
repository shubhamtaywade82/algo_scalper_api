# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'API SMC replays' do
  let(:entry_time) { Time.zone.parse('2026-10-23 09:20:00') }
  let(:exit_time) { Time.zone.parse('2026-10-23 10:05:00') }

  let(:runner_result) do
    {
      symbol: 'NIFTY',
      options_summary: {
        total_pnl_percent: 0.12,
        total_trades: 3,
        win_rate: 66.7,
        winning_trades: 2,
        losing_trades: 1,
        expectancy: 0.04,
        trades: [
          { pnl_percent: 10.0 },
          { pnl_percent: -5.0 },
          { pnl_percent: 2.0 }
        ]
      },
      spot_summary: { count: 5, directional_win_rate: 60.0 },
      option_trades: [
        {
          signal_type: 'ce',
          entry_time: entry_time,
          exit_time: exit_time,
          entry_price: 120.5,
          exit_price: 132.75,
          pnl_percent: 10.17,
          exit_reason: 'target'
        }
      ],
      spot_rows: [
        {
          bar_index: 10,
          timestamp: entry_time,
          action: 'buy_ce',
          reason: 'bos',
          rr: 2.0,
          permission: 'granted',
          forward_horizon_bars: 12,
          mfe_up_pct: 0.8,
          mfe_down_pct: 0.2,
          horizon_return_pct: 0.5,
          directional_win: true
        }
      ]
    }
  end

  describe 'POST /api/replays' do
    it 'runs the replay and returns metrics, trades, events and spot rows' do
      allow(Backtest::SmcReplayRunner).to receive(:call).and_return(runner_result)

      post '/api/replays', params: { symbol: 'nifty', days_back: 45 }, as: :json

      expect(response).to have_http_status(:ok)
      body = response.parsed_body

      expect(body['symbol']).to eq('NIFTY')
      expect(body['days_back']).to eq(45)

      metrics = body['metrics']
      expect(metrics['netPnl']).to eq(120.0)
      expect(metrics['netPnlPct']).to eq(0.12)
      expect(metrics['totalTrades']).to eq(3)
      expect(metrics['winRate']).to eq(66.7)
      expect(metrics['profitFactor']).to eq(2.4)
      expect(metrics['expectancy']).to eq(0.04)
      expect(metrics['signalCount']).to eq(5)
      expect(metrics['signalWinRate']).to eq(60.0)

      trade = body['trades'].first
      expect(trade['type']).to eq('BUY')
      expect(trade['inst']).to eq('NIFTY CE')
      expect(trade['qty']).to eq(75)
      expect(trade['entry']).to eq(120.5)
      expect(trade['exit']).to eq(132.75)
      expect(trade['pnl']).to eq(25_425.0)
      expect(trade['pnlPct']).to eq(10.17)
      expect(trade['status']).to eq('WIN')

      event_texts = body['events'].pluck('text')
      expect(event_texts).to include('Market Open')
      expect(event_texts).to include(a_string_matching(/buy_ce signal/))
      expect(event_texts).to include(a_string_matching(/Order placed CE/))
      expect(event_texts).to include(a_string_matching(/Exit \(target\)/))

      spot_row = body['spot_rows'].first
      expect(spot_row['barIndex']).to eq(10)
      expect(spot_row['forwardHorizonBars']).to eq(12)
      expect(spot_row['mfeUpPct']).to eq(0.8)
      expect(spot_row['directionalWin']).to be(true)
    end

    it 'defaults symbol to NIFTY and clamps days_back into the 30..180 window' do
      allow(Backtest::SmcReplayRunner).to receive(:call).and_return(runner_result)

      post '/api/replays', params: { days_back: 500 }, as: :json

      expect(Backtest::SmcReplayRunner).to have_received(:call)
        .with(hash_including(symbol: 'NIFTY', days_back: 180, permission_mode: 'strict', simulate_options: true))
      expect(response.parsed_body['days_back']).to eq(180)
    end

    it 'raises small day requests to the 30-day default' do
      allow(Backtest::SmcReplayRunner).to receive(:call).and_return(runner_result)

      post '/api/replays', params: { days_back: 5 }, as: :json

      expect(response.parsed_body['days_back']).to eq(30)
    end

    it 'renders 422 with the runner error when the replay cannot run' do
      allow(Backtest::SmcReplayRunner).to receive(:call).and_return({ error: 'insufficient_bars' })

      post '/api/replays', params: {}, as: :json

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body['error']).to eq('insufficient_bars')
    end

    it 'renders 500 replay_failed when the runner raises' do
      allow(Backtest::SmcReplayRunner).to receive(:call).and_raise(StandardError, 'boom')

      post '/api/replays', params: {}, as: :json

      expect(response).to have_http_status(:internal_server_error)
      expect(response.parsed_body['error']).to eq('replay_failed')
    end
  end
end
