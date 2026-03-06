# frozen_string_literal: true

# Background job that computes and stores analysis results for all indices.
# Runs periodically (triggered by scheduler or manual enqueue).
# Each component (SMC, AI, Regime) is computed independently and stored
# via AnalysisStore so the API endpoint always returns instantly from cache.
#
# Usage:
#   AnalysisJob.perform_later                      # All indices, stale only
#   AnalysisJob.perform_later('NIFTY')             # Single index, stale only
#   AnalysisJob.perform_later('NIFTY', force: true) # Single index, force refresh
#
class AnalysisJob < ApplicationJob
  self.queue_adapter = :async
  queue_as :background

  retry_on StandardError, wait: -> (executions) { 2**executions }, attempts: 2

  AI_TIMEOUT = 45 # seconds

  def perform(index_key = nil, force: false)
    indices = index_key ? [index_key.upcase] : all_index_keys

    indices.each do |key|
      compute_for_index(key, force: force)
      sleep 1 # Rate limit between indices
    end

    Rails.logger.info("[AnalysisJob] Completed analysis for #{indices.join(', ')}")
  rescue StandardError => e
    Rails.logger.error("[AnalysisJob] Fatal error: #{e.class} - #{e.message}")
    raise
  end

  private

  def compute_for_index(index_key, force: false)
    instrument = find_instrument(index_key)
    unless instrument
      Rails.logger.warn("[AnalysisJob] Instrument not found for #{index_key}")
      return
    end

    stale = force ? AnalysisStore::COMPONENTS : AnalysisStore.stale_components(index_key)
    return if stale.empty?

    Rails.logger.info("[AnalysisJob] #{index_key}: refreshing #{stale.join(', ')}")

    # SMC Analysis
    if stale.include?(:smc)
      data = safe_compute("#{index_key}:smc") do
        engine = Smc::BiasEngine.new(instrument, delay_seconds: 0.5)
        engine.details
      end
      AnalysisStore.write(index_key, :smc, data)
    end

    # Market Regime
    if stale.include?(:regime)
      data = safe_compute("#{index_key}:regime") do
        series = instrument.candle_series(interval: '5')
        if series&.candles&.size&.>= 20
          MarketRegimeDetector.new(series).detect
        else
          { regime: 'NO_DATA', confidence: 0 }
        end
      end
      AnalysisStore.write(index_key, :regime, data)
    end

    # AI Analysis (slowest — do last, with timeout)
    if stale.include?(:ai)
      data = safe_compute("#{index_key}:ai") do
        Timeout.timeout(AI_TIMEOUT) do
          engine = Smc::BiasEngine.new(instrument, delay_seconds: 0.5)
          engine.analyze_with_ai
        end
      end
      AnalysisStore.write(index_key, :ai, data)
    end
  end

  def find_instrument(index_key)
    index_cfg = IndexConfigLoader.load_indices.find { |idx| idx[:key].to_s.upcase == index_key }
    return nil unless index_cfg

    Instrument.find_by_sid_and_segment(
      security_id: index_cfg[:sid],
      segment_code: index_cfg[:segment]
    )
  end

  def all_index_keys
    IndexConfigLoader.load_indices.map { |idx| idx[:key].to_s.upcase }
  end

  def safe_compute(label)
    yield
  rescue Timeout::Error
    Rails.logger.warn("[AnalysisJob] #{label} timed out after #{AI_TIMEOUT}s")
    nil
  rescue StandardError => e
    Rails.logger.warn("[AnalysisJob] #{label} failed: #{e.class} - #{e.message}")
    nil
  end
end
