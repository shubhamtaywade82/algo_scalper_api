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

      record_swings(series) + record_bos(series) + record_choch(series) +
        record_fvgs(series) + record_order_blocks(series) + record_liquidity_sweep(series)
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

    def record_bos(series)
      history = Smc::Detectors::Structure.new(series).bos_history
      known = already_emitted_values(event_type: 'bos', field: 'price')

      history.filter_map do |bos|
        price = bos[:price].to_f
        next if known.include?(price)

        publish_event!(event_type: 'bos', payload: { 'price' => price, 'type' => bos[:type].to_s, 'index' => bos[:index] })
      end
    end

    def record_choch(series)
      choch = Smc::Detectors::Structure.new(series).choch?
      return [] unless choch

      price = choch[:price].to_f
      known = already_emitted_values(event_type: 'choch', field: 'price')
      return [] if known.include?(price)

      parent_id = SmcEvent.where(correlation_id: correlation_id, event_type: 'bos')
                          .order(sequence: :desc).limit(1).pick(:id)

      [publish_event!(
        event_type: 'choch',
        payload: { 'price' => price, 'type' => choch[:type].to_s, 'index' => choch[:index] },
        parent_event_id: parent_id
      )]
    end

    def record_fvgs(series)
      gaps = Smc::Detectors::Fvg.new(series).active_gaps
      known = SmcEvent.where(correlation_id: correlation_id, event_type: 'fvg_created')
                      .order(sequence: :desc).limit(50)
                      .pluck(Arel.sql("payload->>'type'"), Arel.sql("(payload->>'from')::float"), Arel.sql("(payload->>'to')::float"))

      gaps.filter_map do |gap|
        identity = [gap[:type].to_s, gap[:from].to_f, gap[:to].to_f]
        next if known.include?(identity)

        publish_event!(
          event_type: 'fvg_created',
          payload: { 'type' => gap[:type].to_s, 'from' => gap[:from].to_f, 'to' => gap[:to].to_f, 'index' => gap[:index] }
        )
      end
    end

    def record_order_blocks(series)
      blocks = Smc::Detectors::OrderBlocks.new(series).active_blocks
      known = SmcEvent.where(correlation_id: correlation_id, event_type: 'order_block_formed')
                      .order(sequence: :desc).limit(50)
                      .pluck(Arel.sql("payload->>'bias'"), Arel.sql("(payload->>'high')::float"), Arel.sql("(payload->>'low')::float"))

      blocks.filter_map do |block|
        identity = [block[:bias].to_s, block[:high].to_f, block[:low].to_f]
        next if known.include?(identity)

        publish_event!(
          event_type: 'order_block_formed',
          payload: { 'bias' => block[:bias].to_s, 'high' => block[:high].to_f, 'low' => block[:low].to_f, 'index' => block[:index] }
        )
      end
    end

    def record_liquidity_sweep(series)
      liquidity = Smc::Detectors::Liquidity.new(series)
      direction = liquidity.sweep_direction
      return [] unless direction

      structure = Smc::Detectors::Structure.new(series)
      level_event_type = direction == :buy_side ? 'swing_high' : 'swing_low'
      level_price = (direction == :buy_side ? structure.last_swing_high : structure.last_swing_low)&.dig(:price)&.to_f
      return [] unless level_price

      last_timestamp = series.candles.last.timestamp.iso8601
      known = SmcEvent.where(correlation_id: correlation_id, event_type: 'liquidity_sweep')
                      .order(sequence: :desc).limit(50)
                      .pluck(Arel.sql("payload->>'direction'"), Arel.sql("(payload->>'level_price')::float"), Arel.sql("payload->>'timestamp'"))
      identity = [direction.to_s, level_price, last_timestamp]
      return [] if known.include?(identity)

      parent_id = SmcEvent.where(correlation_id: correlation_id, event_type: level_event_type)
                          .order(sequence: :desc).limit(50)
                          .find { |e| e.payload['price'].to_f == level_price } # rubocop:disable Lint/FloatComparison -- same jsonb round-trip value, exact match intended
                          &.id

      [publish_event!(
        event_type: 'liquidity_sweep',
        payload: { 'direction' => direction.to_s, 'level_price' => level_price, 'timestamp' => last_timestamp },
        parent_event_id: parent_id
      )]
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
