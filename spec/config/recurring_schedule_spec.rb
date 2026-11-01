# frozen_string_literal: true

require 'rails_helper'

# Every recurring task must be a schedule Solid Queue can parse. An invalid entry
# is silently absent from the scheduler, so a regression here would stop a job
# (e.g. cancel_stuck_orders) without any error at runtime.
RSpec.describe 'config/recurring.yml' do # rubocop:disable RSpec/DescribeClass
  let(:config) { YAML.load_file(Rails.root.join('config/recurring.yml'), aliases: true) }

  %w[development production].each do |env|
    it "has only valid schedules in #{env}" do
      invalid = config.fetch(env).filter_map do |key, options|
        task = SolidQueue::RecurringTask.from_configuration(key, **options.symbolize_keys)
        "#{key}: #{task.errors.full_messages.to_sentence}" unless task.valid?
      end

      expect(invalid).to be_empty
    end
  end

  it 'keeps the four cash-session jobs on their intended cadence in production' do
    production = config.fetch('production')
    schedules = %w[smc_scanner ai_agents_cycle cancel_stuck_orders tick_staleness_sampler].index_with do |key|
      SolidQueue::RecurringTask.from_configuration(key, **production.fetch(key).symbolize_keys)
                               .then { |t| t.send(:parsed_schedule).original }
    end

    expect(schedules).to eq(
      'smc_scanner' => '*/15 9-15 * * 1-5 Asia/Kolkata',
      'ai_agents_cycle' => '*/15 9-15 * * 1-5 Asia/Kolkata',
      'cancel_stuck_orders' => '* 9-15 * * 1-5 Asia/Kolkata',
      'tick_staleness_sampler' => '* 9-15 * * 1-5 Asia/Kolkata'
    )
  end
end
