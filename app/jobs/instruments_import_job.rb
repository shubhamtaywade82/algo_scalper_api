# frozen_string_literal: true

# Daily job to sync the Dhan instrument master (scrip CSV) into the local DB.
# Ensures consolidated Instrument rows exist for current weekly/monthly
# expiries so that strike selection in Options::ChainAnalyzer works correctly.
#
# Optional targeted refresh: pass one or more exchange segments to hit Dhan's
# segmentwise instrument-list API instead of the full CSV — useful for an
# intraday FNO refresh:
#
#   InstrumentsImportJob.perform_later('NSE_FNO')
#   InstrumentsImportJob.perform_later('NSE_FNO', 'BSE_FNO')
class InstrumentsImportJob < ApplicationJob
  queue_as :background

  retry_on StandardError, wait: ->(executions) { 2**executions }, attempts: 3

  def perform(*exchange_segments)
    if exchange_segments.empty?
      Rails.logger.info('[InstrumentsImportJob] Starting full instruments import (CSV master)...')
      summary = InstrumentsImporter.import_from_url
      Rails.logger.info(
        "[InstrumentsImportJob] Completed in #{summary[:duration]&.round(1)}s — " \
        "instruments: #{summary[:instruments_count] || 0}, derivatives: #{summary[:derivatives_count] || 0}"
      )
      return summary
    end

    exchange_segments.each do |segment|
      Rails.logger.info("[InstrumentsImportJob] Starting segmentwise import for #{segment}...")
      summary = Instruments::SegmentImporter.import_segment(segment)
      Rails.logger.info(
        "[InstrumentsImportJob] #{segment} done — rows: #{summary[:rows]}, " \
        "upserts: #{summary[:upserts]}, underlying links: #{summary[:linked]}"
      )
    end
  end
end
