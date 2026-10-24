# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Strategies::Discovery do
  describe '.sync!' do
    it 'sets current_version on the first sync of a newly-discovered strategy' do
      # Regression test: reconcile_plugin! used to gate the current_version update on
      # `strategy_record.name != plugin[:name]`, but find_or_create_by!'s block already
      # sets the name at creation time, so that condition was always false on first sync
      # and current_version silently stayed nil — breaking both Manager (manager.rb:157)
      # and any caller resolving a strategy by slug for the first time.
      described_class.sync!

      record = Strategies::Record.find_by(slug: 'vwap-reversal')

      expect(record).to be_present
      expect(record.current_version).to be_present
      expect(record.current_version.manifest['class_name']).to eq('VwapReversalStrategy')
    end

    it 'keeps current_version pointing at a real, non-stale version across repeated syncs' do
      # NOTE: a separate pre-existing issue (unrelated to the current_version fix above) means
      # each sync! call creates a new Version row regardless of whether source content changed
      # (next_version is always max+1, with no checksum-diff short-circuit) — not fixed here,
      # out of scope for this change. This test only asserts current_version never regresses to
      # nil/stale, which is what the fix above guarantees.
      described_class.sync!
      described_class.sync!

      record = Strategies::Record.find_by(slug: 'vwap-reversal')

      expect(record.current_version).to be_present
      expect(record.current_version.version).to eq(record.versions.maximum(:version))
    end
  end
end
