# frozen_string_literal: true

require 'rails_helper'
require 'yaml'

# rubocop:disable-next RSpec/DescribeClass
RSpec.describe 'recurring schedule config' do
  let(:config) { YAML.load_file(Rails.root.join('config/recurring.yml')) }

  # History: the 2026-04 "event-driven intraday analysis" change (#163) moved
  # every scanner/AI job to post-close 4pm and locked it in with a spec. The
  # refactor/smc-scanner-chat-with-tools merge later restored the SMC scanner
  # to an intraday 15-minute cadence on purpose ("aligns with 15m MTF
  # candles"), and 4606bc51 added the multi-agent AI cycle every 15 minutes
  # during market hours. Heavy AI technical analysis stays post-close.
  it 'schedules the SMC scanner every 15 minutes to align with 15m MTF candles' do
    expect(config.dig('development', 'smc_scanner', 'schedule')).to eq('every 15 minutes')
    # Production is scoped to market hours on weekdays.
    expect(config.dig('production', 'smc_scanner', 'schedule'))
      .to eq('every 15 minutes between 9:15am and 3:30pm on weekdays')
  end

  it 'runs the multi-agent AI cycle every 15 minutes' do
    expect(config.dig('development', 'ai_agents_cycle', 'schedule')).to eq('every 15 minutes')
    expect(config.dig('production', 'ai_agents_cycle', 'schedule'))
      .to eq('every 15 minutes between 9:15am and 3:30pm on weekdays')
  end

  it 'keeps heavy AI technical analysis post-close instead of intraday' do
    %w[development production].each do |env|
      nifty_schedule = config.dig(env, 'ai_technical_analysis_nifty', 'schedule')
      sensex_schedule = config.dig(env, 'ai_technical_analysis_sensex', 'schedule')

      expect(nifty_schedule).to include('at 4:00pm')
      expect(sensex_schedule).to include('at 4:00pm')
      expect(nifty_schedule).not_to include('every 15 minutes')
      expect(sensex_schedule).not_to include('every 15 minutes')
    end
  end
end
