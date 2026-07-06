# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Strategies::DeployPipeline do
  let(:slug) { 'test_strategy' }
  let(:strategy_dir) { Rails.root.join('strategies', slug) }

  before do
    strategy_dir.mkpath
    strategy_dir.join('manifest.yml').write(<<~YAML)
      slug: #{slug}
      name: Test Strategy
      class_name: TestStrategy
      params: {}
      instruments:
        - NIFTY
      timeframes:
        - 1m
    YAML
    strategy_dir.join('strategy.rb').write(<<~RUBY)
      class TestStrategy < Strategies::Base
        def call(context) = nil
      end
    RUBY
  end

  after do
    FileUtils.rm_rf(strategy_dir)
    strategy_record = Strategies::Record.find_by(slug: slug)
    strategy_record&.destroy
  end

  describe '.call' do
    it 'runs the full pipeline and returns a version' do
      result = described_class.call(slug)
      expect(result[:ok]).to be true
      expect(result[:version]).to be_persisted
      expect(result[:version].version).to eq(1)
      expect(result[:scan_report]).to be_a(Hash)
    end

    it 'creates a strategy record on first deploy' do
      expect { described_class.call(slug) }
        .to change(Strategies::Record, :count).by(1)
      expect(Strategies::Record.find_by(slug: slug).status).to eq('deployed')
    end

    it 'increments version on redeploy' do
      described_class.call(slug)
      result = described_class.call(slug)
      expect(result[:version].version).to eq(2)
    end

    it 'snapshots the strategy file to releases/' do
      described_class.call(slug)
      expect(strategy_dir.join('releases', 'v1', 'strategy.rb')).to exist
    end
  end

  context 'when manifest is missing' do
    before { strategy_dir.join('manifest.yml').delete }

    it 'returns errors' do
      result = described_class.call(slug)
      expect(result[:ok]).to be false
      expect(result[:errors]).to be_present
    end
  end

  context 'when strategy has security blocker' do
    before do
      strategy_dir.join('strategy.rb').write(<<~RUBY)
        class TestStrategy < Strategies::Base
          def call(context)
            system("rm -rf /")
            nil
          end
        end
      RUBY
    end

    it 'fails the deploy' do
      result = described_class.call(slug)
      expect(result[:ok]).to be false
      expect(result[:scan_report][:blocked_count]).to be >= 1
    end
  end
end
