# frozen_string_literal: true

module Positions
  module MetadataResolver
    module_function

    def index_key(tracker)
      key = tracker.index_key if tracker.respond_to?(:index_key)
      return key if key.present?

      derivative = tracker.watchable if tracker.watchable.is_a?(Derivative)
      return derivative.underlying_symbol if derivative&.underlying_symbol.present?

      instrument = tracker.instrument
      return instrument.underlying_symbol if instrument.respond_to?(:underlying_symbol) &&
                                             instrument.underlying_symbol.present?

      tracker.symbol
    rescue StandardError
      nil
    end

    def direction(tracker)
      dir = tracker.direction if tracker.respond_to?(:direction)
      return dir.to_s.downcase.to_sym if dir.present?

      side = tracker.side.to_s.downcase
      return :bearish if side.include?('sell') || side.include?('short')

      derivative = tracker.watchable if tracker.watchable.is_a?(Derivative)
      return :bearish if derivative&.option_type.to_s.upcase == 'PE'

      :bullish
    rescue StandardError
      :bullish
    end

    def underlying_meta(tracker, index_key: nil)
      derivative = tracker.watchable if tracker.watchable.is_a?(Derivative)
      if derivative&.underlying_security_id.present?
        segment = derivative.instrument&.exchange_segment || 'IDX_I'
        return {
          segment: segment,
          security_id: derivative.underlying_security_id.to_s,
          symbol: derivative.underlying_symbol || tracker.symbol,
          index_key: derivative.underlying_symbol || tracker.symbol
        }
      end

      instrument = tracker.instrument
      if instrument&.exchange_segment&.to_s&.upcase == 'IDX_I'
        return {
          segment: instrument.exchange_segment,
          security_id: instrument.security_id.to_s,
          symbol: instrument.symbol_name,
          index_key: instrument.symbol_name
        }
      end

      key = index_key || index_key(tracker)
      cfg = index_config_for_key(key)
      return unless cfg

      {
        segment: (cfg[:segment] || cfg['segment']).to_s,
        security_id: (cfg[:sid] || cfg['sid']).to_s,
        symbol: (cfg[:key] || cfg['key']).to_s,
        index_key: (cfg[:key] || cfg['key']).to_s
      }
    rescue StandardError
      nil
    end

    def index_config_for_key(key)
      return nil if key.blank?

      IndexConfigLoader.load_indices.find do |cfg|
        candidate = cfg[:key] || cfg['key']
        candidate.to_s.casecmp?(key.to_s)
      end
    rescue StandardError
      nil
    end
  end
end
