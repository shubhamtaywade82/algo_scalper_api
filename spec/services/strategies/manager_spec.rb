# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Strategies::Manager do
  subject(:manager) { described_class.new }

  before do
    Core::EventBus.instance.clear
  end

  after do
    manager.stop
    Core::EventBus.instance.clear
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
      path = Rails.root.join("tmp/lifecycle_test_strategy.rb")
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

    let(:path) { Rails.root.join("tmp/lifecycle_test_strategy.rb") }

    before do
      strategy_record.update!(current_version: version)
    end

    after do
      FileUtils.rm_f(path)
    end

    it 'start_runner works when called directly' do
      manager.send(:start_runner, strategy_record)
      expect(manager.runner_status('lifecycle_test')).not_to be_nil
    end

    it 'reconcile detects and starts a runner' do
      manager.send(:reconcile)
      expect(manager.runner_status('lifecycle_test')).not_to be_nil
    end

    it 'reconcile stops a runner when desired_status is stopped' do
      manager.send(:reconcile)
      expect(manager.runner_status('lifecycle_test')).not_to be_nil

      strategy_record.update!(desired_status: 'stopped')
      manager.send(:reconcile)

      expect(manager.runner_status('lifecycle_test')).to be_nil
    end
  end
end
