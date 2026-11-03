# frozen_string_literal: true

# Background job that computes and stores analysis results for all indices.
# Runs periodically (triggered by scheduler or manual enqueue).
# Each component (SMC, AI, Regime) is computed independently and stored
# via AnalysisStore so the API endpoint always returns instantly from cache.
#
# Usage:
#   AnalysisJob.perform_later                            # All indices, stale only
#   AnalysisJob.perform_later('NIFTY')                   # Single index, stale only
#   AnalysisJob.perform_later('NIFTY', force: true)      # Single index, force refresh
#   AnalysisJob.perform_later(nil, %w[smc regime])       # recurring.yml: no LLM call
#
# The recurring run is what keeps regime/SMC/Supertrend fresh for the Market Brief;
# before it existed they were only computed while someone had the Analysis page open.
class AnalysisJob < ApplicationJob
  queue_as :background

  retry_on StandardError, wait: ->(executions) { 2**executions }, attempts: 2

  AI_TIMEOUT = 120 # seconds

  # A component that raised. Raised (once) at the end of #perform so already
  # computed components stay cached while the job still fails loudly and
  # retries — instead of writing nil into the analysis store and marking a
  # broken component "fresh" (error-handling review 2026-09).
  class ComponentFailure < StandardError
    attr_reader :failed_components

    def initialize(failed_components)
      @failed_components = failed_components
      super("AnalysisJob components failed: #{failed_components.join(', ')}")
    end
  end

  def perform(index_key = nil, components = nil, force: false)
    indices = index_key ? [index_key.upcase] : all_index_keys
    only = components&.map(&:to_sym)
    failures = []

    indices.each do |key|
      failures.concat(compute_for_index(key, force: force, only: only))
      sleep 1 # Rate limit between indices
    end

    Rails.logger.info("[AnalysisJob] Completed analysis for #{indices.join(', ')}")

    raise ComponentFailure, failures if failures.any?
  rescue StandardError => e
    Rails.logger.error("[AnalysisJob] Fatal error: #{e.class} - #{e.message}")
    raise
  end

  private

  # @return [Array<String>] labels of components that failed (not written)
  def compute_for_index(index_key, force: false, only: nil)
    instrument = find_instrument(index_key)
    unless instrument
      Rails.logger.warn("[AnalysisJob] Instrument not found for #{index_key}")
      return []
    end

    stale = force ? AnalysisStore::COMPONENTS : AnalysisStore.stale_components(index_key)
    stale &= only if only
    return [] if stale.empty?

    Rails.logger.info("[AnalysisJob] #{index_key}: refreshing #{stale.join(', ')}")
    failures = []

    # SMC Analysis
    if stale.include?(:smc)
      failures << compute_component("#{index_key}:smc") do
        AnalysisStore.write(index_key, :smc,
                            Smc::BiasEngine.new(instrument, delay_seconds: 0.5).details)
      end
    end

    # Market Regime
    if stale.include?(:regime)
      failures << compute_component("#{index_key}:regime") do
        series = instrument.candle_series(interval: '5')
        data = if series&.candles&.size&.>= 20
                 MarketRegimeDetector.new(series).detect.merge(supertrend: supertrend_summary(series))
               else
                 { regime: 'NO_DATA', confidence: 0 }
               end
        AnalysisStore.write(index_key, :regime, data)
      end
    end

    # AI Analysis (slowest — do last, with timeout)
    if stale.include?(:ai) && !Ai::GenerativeAiMarketGate.skip?(force: false)
      failures << compute_component("#{index_key}:ai") do
        Timeout.timeout(AI_TIMEOUT) do
          engine = Smc::BiasEngine.new(instrument, delay_seconds: 0.5)
          AnalysisStore.write(index_key, :ai, engine.analyze_with_ai)
        end
      end
    end

    failures.compact
  end

  # Same period/multiplier the signal engine uses (signals.supertrend), so the brief
  # reports the trend the engine trades on rather than a second definition.
  def supertrend_summary(series)
    cfg = AlgoConfig.fetch.dig(:signals, :supertrend) || {}
    result = Indicators::Supertrend.new(series: series, period: cfg[:period] || 10,
                                        base_multiplier: cfg[:base_multiplier] || 2.0).call
    { direction: result[:trend]&.to_s, line: result[:last_value]&.to_f&.round(2) }
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

  # Runs one component. On failure the store is NOT written (the component
  # stays stale and will be retried) and the failure label is returned so
  # #perform can fail the job after the remaining components finish.
  #
  # @return [String, nil] the component label when it failed
  def compute_component(label)
    yield
    nil
  rescue Timeout::Error
    Rails.logger.warn("[AnalysisJob] #{label} timed out after #{AI_TIMEOUT}s")
    label
  rescue StandardError => e
    Rails.logger.error("[AnalysisJob] #{label} failed: #{e.class} - #{e.message}")
    label
  end
end
