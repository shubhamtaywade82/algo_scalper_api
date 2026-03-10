# frozen_string_literal: true

# Daily job to sync DhanHQ instrument master (scrip CSV) into local DB.
# Ensures Derivative records exist for current weekly/monthly expiries
# so that strike selection in Options::ChainAnalyzer works correctly.
class InstrumentsImportJob < ApplicationJob
  queue_as :background

  retry_on StandardError, wait: ->(executions) { 2**executions }, attempts: 3

  def perform
    Rails.logger.info('[InstrumentsImportJob] Starting instruments import...')
    summary = InstrumentsImporter.import_from_url
    Rails.logger.info(
      "[InstrumentsImportJob] Completed in #{summary[:duration]&.round(1)}s — " \
      "instruments: #{summary[:instruments_count] || 0}, derivatives: #{summary[:derivatives_count] || 0}"
    )
  end
end
