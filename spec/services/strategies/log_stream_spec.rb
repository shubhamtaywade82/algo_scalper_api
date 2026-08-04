# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Strategies::LogStream do
  let(:slug) { 'test_strategy' }

  around do |example|
    FileUtils.mkdir_p(described_class::LOG_DIR)
    example.run
  ensure
    FileUtils.rm_f(described_class::LOG_DIR.join("#{slug}.log"))
  end

  describe '#log' do
    it 'writes to the log file' do
      stream = described_class.new(slug)
      stream.log(:info, 'hello world')

      log_path = described_class::LOG_DIR.join("#{slug}.log")
      expect(log_path).to exist
      content = log_path.read
      expect(content).to include('hello world')
      expect(content).to include('INFO')
    end

    it 'creates level-specific convenience methods' do
      stream = described_class.new(slug)
      stream.info('info msg')
      stream.warn('warn msg')
      stream.error('error msg')

      log_path = described_class::LOG_DIR.join("#{slug}.log")
      content = log_path.read
      expect(content).to include('[INFO] info msg')
      expect(content).to include('[WARN] warn msg')
      expect(content).to include('[ERROR] error msg')
    end

    it 'does not raise when Redis is unreachable (degraded)' do
      allow(described_class).to receive(:redis).and_raise(Redis::CannotConnectError)
      stream = described_class.new(slug)

      expect { stream.log(:warn, 'redis down') }.not_to raise_error
      log_path = described_class::LOG_DIR.join("#{slug}.log")
      expect(log_path.read).to include('redis down')
    end
  end

  describe '.fetch' do
    it 'returns an empty array when no logs exist' do
      entries = described_class.fetch('nonexistent')
      expect(entries).to eq([])
    end
  end
end
