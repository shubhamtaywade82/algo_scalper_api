# frozen_string_literal: true

require 'rails_helper'
require 'yaml'

# rubocop:disable RSpec/DescribeClass
RSpec.describe 'recurring schedule config' do
  let(:config) { YAML.load_file(Rails.root.join('config/recurring.yml')) }

  it 'does not schedule intraday 15-minute scanner or AI analysis jobs' do
    %w[development production].each do |env|
      smc_schedule = config.dig(env, 'smc_scanner', 'schedule')
      nifty_schedule = config.dig(env, 'ai_technical_analysis_nifty', 'schedule')
      sensex_schedule = config.dig(env, 'ai_technical_analysis_sensex', 'schedule')

      expect(smc_schedule).not_to include('every 15 minutes')
      expect(nifty_schedule).not_to include('every 15 minutes')
      expect(sensex_schedule).not_to include('every 15 minutes')
    end
  end
end
# rubocop:enable RSpec/DescribeClass
