# frozen_string_literal: true

require 'spec_helper'
require 'logger'
require 'singleton'

module Rails
  def self.logger
    @logger ||= Logger.new(nil)
  end
end

module Risk
  class CircuitBreaker
    include Singleton

    def tripped?
      false
    end
  end
end

module Signal
  class Engine
    def self.run_for(_index_cfg); end
  end
end

class AlgoConfig
  class << self
    def fetch
      { indices: [:nifty_fifty] }
    end
  end
end

require_relative '../../../app/services/signal/scheduler'

RSpec.describe Signal::Scheduler do
  subject(:scheduler) { described_class.instance }

  let(:thread_double) { instance_double(Thread, alive?: true, kill: true, join: true) }

  before do
    existing_thread = scheduler.instance_variable_get(:@thread)
    existing_thread&.kill if existing_thread.is_a?(Thread)
    scheduler.instance_variable_set(:@thread, nil)
    allow(Thread).to receive(:new).and_return(thread_double)
    allow(Risk::CircuitBreaker.instance).to receive(:tripped?).and_return(false)
    allow(Signal::Engine).to receive(:run_for)
  end

  describe '#start!' do
    it 'spawns the scheduler thread only once' do
      scheduler.start!
      scheduler.start!

      expect(Thread).to have_received(:new).once
      expect(scheduler).to be_running
    end
  end

  describe '#stop!' do
    it 'kills the thread and clears the running state' do
      scheduler.start!
      scheduler.stop!

      expect(thread_double).to have_received(:kill)
      expect(thread_double).to have_received(:join).with(2)
      expect(scheduler).not_to be_running
    end
  end
end
