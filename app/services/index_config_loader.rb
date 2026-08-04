# frozen_string_literal: true

# Unified service for loading index configurations
# Prefers WatchlistItems (database) over algo.yml config
# Merges WatchlistItem data with algo.yml configuration
class IndexConfigLoader
  include Singleton

  CACHE_TTL = 30.seconds

  # Load all index configurations from unified source
  # @return [Array<Hash>] Array of index configurations with :key, :segment, :sid, and all algo.yml config
  def self.load_indices
    instance.load_indices
  end

  def initialize
    @cached_indices = nil
    @cached_at = nil
    @watchlist_available = nil
    @watchlist_checked_at = nil
  end

  def load_indices
    return @cached_indices if cached?

    # Try WatchlistItems first (database source of truth)
    watchlist_indices = load_from_watchlist_items
    result = watchlist_indices.any? ? watchlist_indices : load_from_config

    @cached_indices = result
    @cached_at = Time.current
    result
  rescue StandardError => e
    Rails.logger.error("[IndexConfigLoader] Error loading indices: #{e.class} - #{e.message}")
    Rails.logger.debug { e.backtrace.first(5).join("\n") }
    # Final fallback to algo.yml
    @cached_indices = load_from_config
    @cached_at = Time.current
    @cached_indices
  end

  def cached?
    @cached_at && @cached_indices && (Time.current - @cached_at) < CACHE_TTL
  end

  def clear_cache!
    @cached_indices = nil
    @cached_at = nil
    @watchlist_available = nil
    @watchlist_checked_at = nil
  end

  private

  # Load indices from WatchlistItems (database)
  # Merges with algo.yml config to get full configuration
  def load_from_watchlist_items
    return [] unless watchlist_items_available?

    # Load active index watchlist items
    watchlist_items = WatchlistItem.active.where(kind: :index_value).includes(:watchable)
    return [] if watchlist_items.empty?

    # Get algo.yml config for merging
    config_indices = load_from_config

    # Convert WatchlistItems to index configs, merging with algo.yml config
    watchlist_items.filter_map do |item|
      build_index_config_from_watchlist_item(item, config_indices)
    end
  rescue StandardError => e
    Rails.logger.warn("[IndexConfigLoader] Error loading from WatchlistItems: #{e.class} - #{e.message}")
    []
  end

  # Build index config from WatchlistItem, merging with algo.yml config
  def build_index_config_from_watchlist_item(item, config_indices)
    # Get instrument to extract key (symbol_name)
    instrument = item.instrument
    key = if instrument
            instrument.symbol_name
          elsif item.label.present?
            item.label
          else
            # Try to find key from config by matching segment/sid
            find_key_from_config(item.segment, item.security_id, config_indices)
          end

    return nil if key.blank?

    # Find matching config from algo.yml (by key or segment/sid)
    matching_config = find_matching_config(key, item.segment, item.security_id, config_indices)

    # Build base config from WatchlistItem
    base_config = {
      key: key.to_s.upcase,
      segment: item.segment,
      sid: item.security_id.to_s
    }

    # Merge with algo.yml config (algo.yml takes precedence for non-identity fields)
    if matching_config.is_a?(Hash)
      # Merge: WatchlistItem provides identity (segment, sid), algo.yml provides rest
      base_config.merge(matching_config.except(:key, :segment, :sid))
    else
      # No matching config found - use defaults or WatchlistItem data only
      Rails.logger.warn("[IndexConfigLoader] No algo.yml config found for WatchlistItem: #{key} (#{item.segment}/#{item.security_id}) - using minimal config")
      base_config
    end
  end

  # Find matching config from algo.yml by key, segment, or sid
  def find_matching_config(key, segment, security_id, config_indices)
    # First try exact key match
    match = config_indices.find do |cfg|
      cfg_key = cfg[:key] || cfg['key']
      cfg_key.to_s.casecmp?(key.to_s)
    end
    return match if match

    # Then try segment + sid match
    config_indices.find do |cfg|
      cfg_seg = cfg[:segment] || cfg['segment']
      cfg_sid = cfg[:sid] || cfg['sid']
      cfg_seg.to_s == segment.to_s && cfg_sid.to_s == security_id.to_s
    end
  end

  # Find key from config by matching segment/sid
  def find_key_from_config(segment, security_id, config_indices)
    match = config_indices.find do |cfg|
      cfg_seg = cfg[:segment] || cfg['segment']
      cfg_sid = cfg[:sid] || cfg['sid']
      cfg_seg.to_s == segment.to_s && cfg_sid.to_s == security_id.to_s
    end

    match ? (match[:key] || match['key']) : nil
  end

  # Load indices from algo.yml config (fallback)
  def load_from_config
    Array(AlgoConfig.fetch[:indices])
  rescue StandardError => e
    Rails.logger.error("[IndexConfigLoader] Error loading from algo.yml: #{e.class} - #{e.message}")
    []
  end

  # Check if WatchlistItems table exists and has data
  # Cached to avoid repeated database queries
  def watchlist_items_available?
    return @watchlist_available if @watchlist_checked_at &&
                                   (Time.current - @watchlist_checked_at) < 60.seconds

    @watchlist_available = check_watchlist_available
    @watchlist_checked_at = Time.current
    @watchlist_available
  end

  def check_watchlist_available
    return false unless defined?(ActiveRecord)
    return false unless ActiveRecord::Base.connection.schema_cache.data_source_exists?('watchlist_items')

    WatchlistItem.exists?
  rescue StandardError
    false
  end

  # Clear cache (call when WatchlistItems change)
  def clear_cache!
    @watchlist_available = nil
    @watchlist_checked_at = nil
  end
end
