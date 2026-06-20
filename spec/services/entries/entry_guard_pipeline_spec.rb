# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Entries::EntryGuardPipeline do
  describe '.new' do
    it 'includes midday and loss-streak guards in default order' do
      handlers = described_class.new.send(:default_handlers)

      expect(handlers).to include(Entries::Guards::MiddayQualityGuard)
      expect(handlers).to include(Entries::Guards::LossStreakGuard)
      expect(handlers).to include(Entries::Guards::SegmentExpectancyGuard)
      expect(handlers).to include(Entries::Guards::TradingTimeRestrictionGuard)
      expect(handlers).to include(Entries::Guards::IndexTradeLimitGuard)
      expect(handlers.index(Entries::Guards::MiddayQualityGuard)).to be > handlers.index(Entries::Guards::TimeRegimeGuard)
      expect(handlers.index(Entries::Guards::SegmentExpectancyGuard)).to be > handlers.index(Entries::Guards::TimeRegimeGuard)
      expect(handlers.index(Entries::Guards::TradingTimeRestrictionGuard)).to be > handlers.index(Entries::Guards::EarliestEntryGuard)
      expect(handlers.index(Entries::Guards::LossStreakGuard)).to be > handlers.index(Entries::Guards::EdgeFailureGuard)
    end
  end
end
