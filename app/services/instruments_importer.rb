# app/services/instruments_importer.rb
# frozen_string_literal: true

require 'csv'
require 'net/http'
require 'uri'

# Imports the Dhan scrip master into the SINGLE canonical `instruments` table.
#
# Architecture (review 2026-09): one tradable-security master. The legacy
# `derivatives` table is a frozen archive — nothing writes to it anymore.
#
#   * Canonical broker identity: (exchange, segment, security_id), enforced by
#     a DB unique index and used as the upsert conflict target.
#   * FNO rows are linked to their underlying via underlying_instrument_id.
#   * Expired contracts are kept forever (history/backtesting) but flagged
#     tradable = false.
class InstrumentsImporter
  CSV_URL         = 'https://images.dhan.co/api-data/api-scrip-master-detailed.csv'
  CACHE_PATH      = Rails.root.join('tmp/dhan_scrip_master.csv')
  CACHE_MAX_AGE   = 24.hours
  VALID_EXCHANGES = %w[NSE BSE].freeze
  BATCH_SIZE      = 1_000
  FNO_SEGMENT     = 'D'
  UNDERLYING_SEGMENTS = %w[I E].freeze

  # Master attributes refreshed on every import (current-state semantics).
  REFRESHED_COLUMNS = %i[
    symbol_name display_name isin instrument_code instrument_type
    underlying_security_id underlying_symbol series lot_size expiry_date
    strike_price option_type tick_size expiry_flag updated_at
  ].freeze

  class << self
    # ------------------------------------------------------------
    # Public entry points
    # ------------------------------------------------------------
    def import_from_url
      started_at = Time.current
      csv_text   = fetch_csv_with_cache
      summary    = import_from_csv(csv_text)

      finished_at = Time.current
      summary[:started_at]  = started_at
      summary[:finished_at] = finished_at
      summary[:duration]    = finished_at - started_at

      record_success!(summary)
      summary
    end

    def fetch_csv_with_cache
      if CACHE_PATH.exist? && Time.current - CACHE_PATH.mtime < CACHE_MAX_AGE
        # Rails.logger.info "Using cached CSV (#{CACHE_PATH})"
        return CACHE_PATH.read
      end

      # Rails.logger.info 'Downloading fresh CSV from Dhan…'
      csv_text = download_csv(CSV_URL)

      CACHE_PATH.dirname.mkpath
      File.write(CACHE_PATH, csv_text)
      # Rails.logger.info "Saved CSV to #{CACHE_PATH}"

      csv_text
    rescue StandardError => e
      # Rails.logger.warn "CSV download failed: #{e.message}"
      raise e if CACHE_PATH.exist? == false # don’t swallow if no fallback

      # Rails.logger.warn 'Falling back to cached CSV (may be stale)'
      CACHE_PATH.read
    end

    def download_csv(url_string)
      uri = URI.parse(url_string)
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = uri.scheme == 'https'
      http.open_timeout = 15
      http.read_timeout = 120
      path = uri.request_uri.presence || '/'
      request = Net::HTTP::Get.new(path)
      response = http.request(request)
      raise "HTTP #{response.code} fetching instruments CSV" unless response.is_a?(Net::HTTPSuccess)

      response.body
    end

    def import_from_csv(csv_content)
      rows = build_rows(csv_content)
      import = rows.empty? ? nil : import_instruments!(rows)
      linked = link_underlying_instruments!
      expired_flagged = mark_expired_contracts_untradable!

      fno_rows = rows.count { |r| r[:segment] == FNO_SEGMENT }
      {
        instrument_rows: rows.size,
        derivative_rows: fno_rows,
        instruments_count: rows.size,
        derivatives_count: fno_rows,
        instrument_upserts: import&.ids&.size.to_i,
        derivative_upserts: fno_rows,
        underlying_links: linked,
        expired_flagged: expired_flagged,
        instrument_total: Instrument.count,
        derivative_total: Instrument.fno.count
      }
    end

    # ------------------------------------------------------------
    # Post-import housekeeping — public so Instruments::SegmentImporter
    # can reuse the exact same semantics.
    # ------------------------------------------------------------

    # FNO contract -> its underlying index/equity row.
    # Primary match: underlying_security_id (exchange-local).
    # Fallback:     underlying_symbol against index rows.
    # @return [Integer] number of links created/refreshed
    def link_underlying_instruments!
      by_sid = {}
      by_symbol = {}

      Instrument.where(segment: UNDERLYING_SEGMENTS).pluck(:security_id, :symbol_name, :id).each do |sid, sym, id|
        by_sid[sid] = id if sid.present?
        by_symbol[sym.to_s.upcase] = id if sym.present? && !by_symbol.key?(sym.to_s.upcase)
      end

      pairs = []

      Instrument.where(segment: FNO_SEGMENT).find_each do |contract|
        parent_id = by_sid[contract.underlying_security_id] ||
                    by_symbol[contract.underlying_symbol.to_s.upcase]
        next unless parent_id
        next if contract.underlying_instrument_id == parent_id

        pairs << [contract.id, parent_id]
      end

      bulk_link!(pairs)
      pairs.size
    end

    # Expired contracts remain in the master for historical trades and
    # backtesting but must never be selected for new orders.
    # @return [Integer] number of rows flagged
    def mark_expired_contracts_untradable!
      Instrument
        .where(expiry_date: ...Date.current)
        .where.not(tradable: false)
        .update_all(tradable: false, updated_at: Time.current)
    end

    private

    # ------------------------------------------------------------
    # Build attribute rows for every tradable security (all segments)
    # ------------------------------------------------------------
    def build_rows(csv_content)
      instruments = []

      CSV.parse(csv_content, headers: true).each do |row|
        next unless VALID_EXCHANGES.include?(row['EXCH_ID'])

        instruments << build_attrs(row).slice(*Instrument.column_names.map(&:to_sym))
      end

      instruments
    end

    def build_attrs(row)
      now = Time.zone.now
      {
        security_id: row['SECURITY_ID'],
        exchange: row['EXCH_ID'],
        segment: row['SEGMENT'],
        isin: row['ISIN'],
        instrument_code: row['INSTRUMENT'],
        underlying_security_id: row['UNDERLYING_SECURITY_ID'],
        underlying_symbol: row['UNDERLYING_SYMBOL'],
        symbol_name: row['SYMBOL_NAME'],
        display_name: row['DISPLAY_NAME'],
        instrument_type: row['INSTRUMENT_TYPE'],
        series: row['SERIES'],
        lot_size: row['LOT_SIZE']&.to_i,
        expiry_date: safe_date(row['SM_EXPIRY_DATE']),
        strike_price: row['STRIKE_PRICE']&.to_f,
        option_type: row['OPTION_TYPE'],
        tick_size: row['TICK_SIZE']&.to_f,
        expiry_flag: row['EXPIRY_FLAG'],
        bracket_flag: row['BRACKET_FLAG'],
        cover_flag: row['COVER_FLAG'],
        asm_gsm_flag: row['ASM_GSM_FLAG'],
        asm_gsm_category: row['ASM_GSM_CATEGORY'],
        buy_sell_indicator: row['BUY_SELL_INDICATOR'],
        buy_co_min_margin_per: row['BUY_CO_MIN_MARGIN_PER']&.to_f,
        sell_co_min_margin_per: row['SELL_CO_MIN_MARGIN_PER']&.to_f,
        buy_co_sl_range_max_perc: row['BUY_CO_SL_RANGE_MAX_PERC']&.to_f,
        sell_co_sl_range_max_perc: row['SELL_CO_SL_RANGE_MAX_PERC']&.to_f,
        buy_co_sl_range_min_perc: row['BUY_CO_SL_RANGE_MIN_PERC']&.to_f,
        sell_co_sl_range_min_perc: row['SELL_CO_SL_RANGE_MIN_PERC']&.to_f,
        buy_bo_min_margin_per: row['BUY_BO_MIN_MARGIN_PER']&.to_f,
        sell_bo_min_margin_per: row['SELL_BO_MIN_MARGIN_PER']&.to_f,
        buy_bo_sl_range_max_perc: row['BUY_BO_SL_RANGE_MAX_PERC']&.to_f,
        sell_bo_sl_range_max_perc: row['SELL_BO_SL_RANGE_MAX_PERC']&.to_f,
        buy_bo_sl_range_min_perc: row['BUY_BO_SL_RANGE_MIN_PERC']&.to_f,
        sell_bo_sl_min_range: row['SELL_BO_SL_MIN_RANGE']&.to_f,
        buy_bo_profit_range_max_perc: row['BUY_BO_PROFIT_RANGE_MAX_PERC']&.to_f,
        sell_bo_profit_range_max_perc: row['SELL_BO_PROFIT_RANGE_MAX_PERC']&.to_f,
        buy_bo_profit_range_min_perc: row['BUY_BO_PROFIT_RANGE_MIN_PERC']&.to_f,
        sell_bo_profit_range_min_perc: row['SELL_BO_PROFIT_RANGE_MIN_PERC']&.to_f,
        mtf_leverage: row['MTF_LEVERAGE']&.to_f,
        created_at: now,
        updated_at: now
      }
    end

    # ------------------------------------------------------------
    # Upsert into the single master on the canonical identity
    # ------------------------------------------------------------
    def import_instruments!(rows)
      Instrument.import(
        rows,
        batch_size: BATCH_SIZE,
        on_duplicate_key_update: {
          conflict_target: %i[exchange segment security_id],
          columns: REFRESHED_COLUMNS
        }
      ).tap do |res|
        # Rails.logger.info "Upserted Instruments: #{res.ids.size}"
      end
    end

    def bulk_link!(pairs)
      pairs.each_slice(500) do |slice|
        values = slice.map { |id, parent_id| "WHEN #{id} THEN #{parent_id}" }.join(' ')
        ids = slice.map(&:first).join(',')
        ActiveRecord::Base.connection.execute(
          "UPDATE instruments SET underlying_instrument_id = CASE id #{values} END WHERE id IN (#{ids})"
        )
      end
    end

    # ------------------------------------------------------------
    # Helpers
    # ------------------------------------------------------------
    def safe_date(str)
      Date.parse(str)
    rescue StandardError
      nil
    end

    def record_success!(summary)
      Setting.put('instruments.last_imported_at', summary[:finished_at].iso8601)
      Setting.put('instruments.last_import_duration_sec', summary[:duration].to_f.round(2))
      Setting.put('instruments.last_instrument_rows', summary[:instrument_rows])
      Setting.put('instruments.last_derivative_rows', summary[:derivative_rows])
      Setting.put('instruments.last_instrument_upserts', summary[:instrument_upserts])
      Setting.put('instruments.last_derivative_upserts', summary[:derivative_upserts])
      Setting.put('instruments.instrument_total', summary[:instrument_total])
      Setting.put('instruments.derivative_total', summary[:derivative_total])
    end
  end
end
