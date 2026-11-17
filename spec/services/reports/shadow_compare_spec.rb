# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Reports::ShadowCompare do
  subject(:result) { described_class.new(date: date, journal_dir: journal_dir).call }

  let(:date) { Date.new(2026, 11, 13) }
  let(:journal_dir) { Pathname.new(Dir.mktmpdir('agent-journal')) }
  let(:instrument) { create(:instrument) }

  after { FileUtils.remove_entry(journal_dir) }

  def write_agent_trade(id:, underlying:, option_type:, filled_at:, pnl:, mode: 'paper')
    events = [
      { ts: filled_at.utc.iso8601, type: 'entry_filled', correlationId: id, underlying: underlying, mode: mode },
      { ts: (filled_at + 20.minutes).utc.iso8601, type: 'trade_closed', positionId: id, underlying: underlying,
        optionType: option_type, pnlInr: pnl, mode: mode }
    ]
    File.open(journal_dir.join('events-2026-11-13.jsonl'), 'a') { |f| events.each { |e| f.puts(e.to_json) } }
  end

  def rails_trade(index_key:, side:, entered_at:, pnl:)
    create(:position_tracker, instrument: instrument, index_key: index_key, side: side, status: 'exited', paper: true,
                              created_at: entered_at, exited_at: entered_at + 15.minutes, last_pnl_rupees: pnl)
  end

  it 'matches trades on the same index and direction that entered within the window' do
    at = Time.zone.local(2026, 11, 13, 9, 20)
    write_agent_trade(id: 'a1', underlying: 'NIFTY', option_type: 'CE', filled_at: at + 4.minutes, pnl: 900)
    rails_trade(index_key: 'NIFTY', side: 'long_ce', entered_at: at, pnl: 400)

    expect(result[:matched].size).to eq(1)
    expect(result[:rails_only]).to be_empty
    expect(result[:agent_only]).to be_empty
  end

  it 'reports a trade only one side took, including opposite directions on the same index' do
    at = Time.zone.local(2026, 11, 13, 10, 0)
    write_agent_trade(id: 'a1', underlying: 'NIFTY', option_type: 'PE', filled_at: at, pnl: -200)
    rails_trade(index_key: 'NIFTY', side: 'long_ce', entered_at: at, pnl: 300)

    expect(result[:matched]).to be_empty
    expect(result[:rails_only].size).to eq(1)
    expect(result[:agent_only].size).to eq(1)
  end

  it 'totals each side separately so the two results can be compared' do
    at = Time.zone.local(2026, 11, 13, 9, 30)
    write_agent_trade(id: 'a1', underlying: 'NIFTY', option_type: 'CE', filled_at: at, pnl: 1_000)
    rails_trade(index_key: 'BANKNIFTY', side: 'long_pe', entered_at: at, pnl: -250)

    expect(result[:totals]).to eq(rails: { trades: 1, pnl: -250.0 }, agent: { trades: 1, pnl: 1_000.0 })
  end

  it 'ignores agent events from other modes so a live run never mixes into a paper comparison' do
    at = Time.zone.local(2026, 11, 13, 9, 30)
    write_agent_trade(id: 'a1', underlying: 'NIFTY', option_type: 'CE', filled_at: at, pnl: 500, mode: 'live')

    expect(result[:agent_only]).to be_empty
  end

  it 'says so plainly when the agent has no journal for the day' do
    expect(result[:agent_journal]).to eq(:missing)
  end

  describe '.render' do
    it 'lists each side\'s unmatched trades and the per-side totals' do
      at = Time.zone.local(2026, 11, 13, 10, 0)
      write_agent_trade(id: 'a1', underlying: 'SENSEX', option_type: 'PE', filled_at: at, pnl: -200)
      rails_trade(index_key: 'NIFTY', side: 'long_ce', entered_at: at, pnl: 300)

      report = described_class.render(date, result)

      expect(report).to include('Rails    1 trades')
      expect(report).to match(/Rails only:\n  rails NIFTY bullish 10:00 \+300/)
      expect(report).to match(/Agent only:\n  agent SENSEX bearish 10:00 -200/)
    end
  end
end
