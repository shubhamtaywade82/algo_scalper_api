# frozen_string_literal: true

FactoryBot.define do
  factory :strategy_record, class: 'Strategies::Record' do
    sequence(:slug) { |n| "strategy_#{n}" }
    sequence(:name) { |n| "Strategy #{n}" }
    status { 'draft' }
  end

  factory :strategy_version, class: 'Strategies::Version' do
    strategy_record
    sequence(:version) { |n| n }
    file_path { Rails.root.join('tmp', "strategy_v#{version}.rb").to_s }
    checksum { Digest::SHA256.hexdigest('class TestStrategy; end') }
    manifest { { 'class_name' => 'TestStrategy', 'params' => {} } }
    deployed_at { Time.current }
  end

  factory :strategy_run, class: 'Strategies::Run' do
    strategy_record
    strategy_version
    started_at { Time.current }
    stats { {} }
  end

  factory :strategy_signal, class: 'Strategies::Signal' do
    strategy_record
    strategy_version
    strategy_run
    instrument_key { 'NIFTY' }
    action { 'hold' }
    outcome { 'shadow' }
    emitted_at { Time.current }
  end

  factory :platform_variable do
    sequence(:key) { |n| "var_#{n}" }
    value_type { 'string' }
    string_value { 'test' }
    scope { 'global' }
    secret { false }
  end
end
