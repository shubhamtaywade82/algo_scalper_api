# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Entries::EntryGuardPipeline do
  describe '.new' do
    it 'includes midday and loss-streak guards in default order' do
      handlers = described_class.new.send(:default_handlers)

      expect(handlers).to include(Entries::Guards::MiddayQualityGuard)
      expect(handlers).to include(Entries::Guards::LossStreakGuard)
      expect(handlers.index(Entries::Guards::MiddayQualityGuard)).to be > handlers.index(Entries::Guards::TimeRegimeGuard)
      expect(handlers.index(Entries::Guards::LossStreakGuard)).to be > handlers.index(Entries::Guards::EdgeFailureGuard)
    end
  end

  describe '#run' do
    it 'returns PASS when all handlers pass' do
      passing_handler = ->(_ctx) { described_class::PASS }
      pipeline = described_class.new([passing_handler])

      expect(pipeline.run({})).to eq(described_class::PASS)
    end

    it 'normalizes blocked hash into a DecisionRejection object' do
      blocking_handler = ->(_ctx) { { blocked: 'Daily loss limit reached' } }
      pipeline = described_class.new([blocking_handler])

      result = pipeline.run({})
      expect(result).to be_a(Entries::DecisionRejection)
      expect(result.code).to eq(:daily_loss_limit_reached)
      expect(result.rejected?).to be true
    end
  end
end
