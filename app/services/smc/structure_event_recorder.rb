# frozen_string_literal: true

module Smc
  # Emits atomic structural events (swings, BOS, CHoCH, FVGs, order blocks,
  # liquidity sweeps) as append-only SmcEvent rows, one row per genuinely-new
  # event, deduped against what's already persisted for this instrument/interval.
  class StructureEventRecorder
    STREAM = 'SMC-STRUCTURE'
    MIN_CANDLES = 5

    def self.record!(instrument:, interval:)
      new(instrument: instrument, interval: interval).record!
    end

    def initialize(instrument:, interval:)
      @instrument = instrument
      @interval = interval
      @correlation_id = "SMC-STRUCT-#{instrument.symbol_name}-#{interval}"
    end

    def record!
      return [] unless event_store_enabled?

      series = @instrument.candles(interval: @interval)
      return [] if series.nil? || series.candles.size < MIN_CANDLES

      record_swings(series)
    end

    private

    attr_reader :correlation_id

    def event_store_enabled?
      AlgoConfig.fetch.dig(:signals, :smc_event_store_publish) == true
    rescue StandardError
      false
    end

    def record_swings(series)
      swings = Smc::Detectors::Structure.new(series).swings
      known_highs = already_emitted_values(event_type: 'swing_high', field: 'price')
      known_lows = already_emitted_values(event_type: 'swing_low', field: 'price')

      events = []
      swings.each do |swing|
        price = swing[:price].to_f
        if swing[:type] == :high && known_highs.exclude?(price)
          events << publish_event!(event_type: 'swing_high', payload: { 'price' => price, 'index' => swing[:index] })
        elsif swing[:type] == :low && known_lows.exclude?(price)
          events << publish_event!(event_type: 'swing_low', payload: { 'price' => price, 'index' => swing[:index] })
        end
      end
      events
    end

    def already_emitted_values(event_type:, field:)
      SmcEvent.where(correlation_id: correlation_id, event_type: event_type)
              .order(sequence: :desc).limit(50)
              .pluck(Arel.sql("(payload->>'#{field}')::float"))
              .compact
    end

    def publish_event!(event_type:, payload:, parent_event_id: nil)
      full_payload = payload.merge('parent_event_id' => parent_event_id)
      EventStore::Publisher.publish!(
        stream: STREAM,
        event_type: event_type,
        correlation_id: correlation_id,
        payload: full_payload,
        validate_contract: false
      )
    end
  end
end
