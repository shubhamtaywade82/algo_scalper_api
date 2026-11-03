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

      strategy_record.reload.update!(desired_status: 'stopped')
      manager.send(:reconcile)

      expect(manager.runner_status('lifecycle_test')).to be_nil
    end

    it 'removes the Runtime registry entry under the manifest class_name on stop' do
      # The registry key is the manifest class_name ("LifecycleTestStrategy"),
      # not slug.camelize ("LifecycleTest") — the old remove missed by that
      # mismatch for 6 of 8 shipped strategies and leaked the anonymous module
      # on every stop (review P2).
      manager.send(:start_runner, strategy_record)
      expect(Strategies::Runtime.lookup('LifecycleTestStrategy')).not_to be_nil

      manager.send(:stop_runner, 'lifecycle_test', 'manual')

      expect(Strategies::Runtime.lookup('LifecycleTestStrategy')).to be_nil
    end
  end

  describe '#attempt_entry expiry window' do
    let(:record) { instance_double(Strategies::Signal, confidence: 0.9, update!: true) }

    before do
      allow(manager).to receive(:auto_entry_enabled?).and_return(true)
      allow(IndexConfigLoader).to receive(:load_indices).and_return([{ key: 'BANKNIFTY' }])
      allow(Options::ChainAnalyzer).to receive(:pick_strikes)
      allow(Entries::EntryGuard).to receive(:try_enter)
    end

    it 'blocks the entry before any strike is picked when the nearest expiry is beyond the window' do
      allow(Signal::ExpiryGate).to receive(:beyond_entry_window?).and_return(true)

      manager.send(:attempt_entry, record, 'BANKNIFTY', 'buy_call')

      expect(record).to have_received(:update!).with(outcome: 'blocked_by_guard', reason: 'expiry_beyond_entry_window')
      expect(Options::ChainAnalyzer).not_to have_received(:pick_strikes)
      expect(Entries::EntryGuard).not_to have_received(:try_enter)
    end
  end
end
