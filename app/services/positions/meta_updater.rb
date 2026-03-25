# frozen_string_literal: true

module Positions
  class MetaUpdater < ApplicationService
    def initialize(tracker:)
      @tracker = tracker
    end

    def update!
      tracker.with_lock do
        tracker.reload
        updated_meta = yield(safe_meta.dup)
        tracker.update!(meta: updated_meta)
      end
    end

    private

    attr_reader :tracker

    def safe_meta
      tracker[:meta].is_a?(Hash) ? tracker[:meta] : {}
    end
  end
end
