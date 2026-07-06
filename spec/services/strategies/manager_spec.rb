# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Strategies::Manager do
  subject(:manager) { described_class.new(context_builder: context_builder) }

  let(:context_builder) { instance_double(Strategies::ContextBuilder) }
  let(:event_bus) { Core::EventBus.instance }

  before do
    event_bus.clear
    allow(context_builder).to receive(:logger=)
  end

  after do
    manager.stop
    event_bus.clear
  end

  describe '#start/#stop' do
    it 'starts and stops cleanly' do
      expect { manager.start }.not_to raise_error
      expect(manager.healthy?).to be true
      manager.stop
      expect(manager.healthy?).to be false
    end
  end

  describe '#runner_status' do
    it 'returns nil for unknown slug' do
      expect(manager.runner_status('nope')).to be_nil
    end
  end

  describe '#all_statuses' do
    it 'returns empty hash when no runners' do
      expect(manager.all_statuses).to eq({})
    end
  end

  describe 'runner lifecycle' do
    let(:strategy_record) do
      create(:strategy_record, slug: 'lifecycle_test', status: 'deployed', desired_status: 'running')
    end
    let(:version) do
      path = Rails.root.join('tmp', 'lifecycle_test_strategy.rb')
      content = <<~RUBY
        class LifecycleTestStrategy < Strategies::Base
          def call(context) = nil
        end
      RUBY
      File.write(path, content)
      create(:strategy_version,
             strategy_record: strategy_record,
             version: 1,
             file_path: path.to_s,
             checksum: Digest::SHA256.hexdigest(content),
             manifest: { 'class_name' => 'LifecycleTestStrategy', 'params' => {} })
    end

    before do
      strategy_record.update!(current_version: version)
      allow(context_builder).to receive(:build).and_return(
        instance_double(Strategies::StrategyContext, instrument_key: 'NIFTY')
      )
    end

    after do
      FileUtils.rm_f(Rails.root.join('tmp', 'lifecycle_test_strategy.rb'))
    end

    it 'reconciles and starts a runner for a strategy with desired_status running' do
      manager.start
      sleep 0.5

      status = manager.runner_status('lifecycle_test')
      expect(status).not_to be_nil
      expect(status[:status]).to eq('running')
    end

    it 'stops a runner when desired_status changes' do
      manager.start
      sleep 0.5
      expect(manager.runner_status('lifecycle_test')).not_to be_nil

      strategy_record.update!(desired_status: 'stopped')
      sleep 0.5

      expect(manager.runner_status('lifecycle_test')).to be_nil
    end
  end
end
