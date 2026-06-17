# frozen_string_literal: true

module DbSeeds
  module_function

  def seed_default_index_watchlist
    created = 0
    IndexConfigLoader.load_indices.each do |cfg|
      instrument = Instrument.find_by_sid_and_segment(
        security_id: cfg[:sid],
        segment_code: cfg[:segment]
      )
      unless instrument
        Rails.logger.debug { "[DbSeeds] Skipping #{cfg[:key]}: index instrument not in DB (run instruments:import)" }
        next
      end

      wl = WatchlistItem.find_or_initialize_by(
        segment: instrument.exchange_segment,
        security_id: instrument.security_id
      )
      wl.label = cfg[:key].to_s
      wl.kind = :index_value
      wl.active = true
      wl.watchable = instrument
      wl.save!
      created += 1
    end

    Rails.logger.debug { "Seeded/Ensured #{created} index watchlist items with associations" }
    created
  end
end
