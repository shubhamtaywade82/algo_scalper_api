# frozen_string_literal: true

require 'rails_helper'

RSpec.describe AlgoConfig do
  around do |example|
    previous = ENV.fetch('RUN_MODE', nil)
    example.run
  ensure
    if previous
      ENV['RUN_MODE'] = previous
    else
      ENV.delete('RUN_MODE')
    end
    described_class.reset!
  end

  describe '.run_mode' do
    it 'returns RUN_MODE env when set' do
      ENV['RUN_MODE'] = 'exit_testing'
      described_class.reset!

      expect(described_class.run_mode).to eq('exit_testing')
    end

    it 'returns run_mode from fetch when RUN_MODE is unset' do
      allow(described_class).to receive(:fetch).and_return({ run_mode: 'entry_testing' })

      expect(described_class.run_mode).to eq('entry_testing')
    end

    it 'defaults to production when missing' do
      allow(described_class).to receive(:fetch).and_return({})

      expect(described_class.run_mode).to eq('production')
    end
  end
end
