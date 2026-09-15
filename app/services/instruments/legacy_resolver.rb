# frozen_string_literal: true

module Instruments
  # Resolves traded-contract references across the consolidation boundary.
  #
  # Context: the legacy `derivatives` table is frozen but historical picks /
  # admin params may still carry Derivative ids. New code carries Instrument
  # ids. Both tables have overlapping integer id ranges, so resolution needs
  # one careful implementation instead of ad-hoc fallbacks scattered through
  # guards and services.
  module LegacyResolver
    module_function

    # Resolves an entry pick (hash with symbol or string keys) to the traded
    # Instrument.
    #
    # Key precedence: instrument_id (new) > derivative_id (legacy) >
    # security_id (fallback).
    #
    # @param pick [Hash]
    # @return [Instrument, nil]
    def resolve_pick(pick)
      return nil if pick.nil?

      instrument_id = pick[:instrument_id] || pick['instrument_id']
      return Instrument.find_by(id: instrument_id) if instrument_id.present?

      derivative_id = pick[:derivative_id] || pick['derivative_id']
      if derivative_id.present?
        instrument = by_legacy_id(derivative_id, require_derivative: true)
        return instrument if instrument
      end

      security_id = (pick[:security_id] || pick['security_id']).to_s
      return nil if security_id.empty?

      Instrument.fno.find_by(security_id: security_id) ||
        Instrument.find_by(security_id: security_id)
    rescue StandardError
      nil
    end

    # Resolves an id that may come from either the Instrument id space (new)
    # or the frozen Derivative id space (legacy).
    #
    # A direct Instrument hit that is itself a derivative contract always
    # wins. Otherwise, if a legacy Derivative with that id has a consolidated
    # mirror, the mirror wins — this disambiguates the overlapping id ranges.
    #
    # @param id [Integer, String]
    # @param require_derivative [Boolean] when true, only option/future
    #   contracts are acceptable matches
    # @return [Instrument, nil]
    def by_legacy_id(id, require_derivative: false)
      instrument = Instrument.find_by(id: id)
      return instrument if instrument&.derivative?

      legacy = Derivative.find_by(id: id)
      if legacy
        mirrored = legacy.consolidated_instrument
        instrument = mirrored if mirrored&.derivative?
      end

      return nil if require_derivative && instrument && !instrument.derivative?

      instrument
    rescue StandardError
      nil
    end
  end
end
