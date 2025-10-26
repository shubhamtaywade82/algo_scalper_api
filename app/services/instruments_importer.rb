# app/services/instruments_importer.rb
# frozen_string_literal: true

require 'csv'
require 'open-uri'

class InstrumentsImporter
  CSV_URL         = 'https://images.dhan.co/api-data/api-scrip-master-detailed.csv'
  CACHE_PATH      = Rails.root.join('tmp/dhan_scrip_master.csv') # ← NEW
  CACHE_MAX_AGE   = 24.hours # ← NEW
  VALID_EXCHANGES = %w[NSE BSE].freeze
  BATCH_SIZE      = 1_000

  class << self
    # ------------------------------------------------------------
    # Public entry point
    # ------------------------------------------------------------
    def import_from_url
      started_at = Time.current
      csv_text   = fetch_csv_with_cache # ← NEW (was: URI.open(CSV_URL).read)
      summary    = import_from_csv(csv_text)

      finished_at = Time.current
      summary[:started_at]  = started_at
      summary[:finished_at] = finished_at
      summary[:duration]    = finished_at - started_at

      record_success!(summary)
      summary
    end

    # ------------------------------------------------------------
    # Fetch CSV with 24-hour cache
    # ------------------------------------------------------------
    # ← NEW helper
    def fetch_csv_with_cache
      if CACHE_PATH.exist? && Time.current - CACHE_PATH.mtime < CACHE_MAX_AGE
        Rails.logger.info "Using cached CSV (#{CACHE_PATH})"
        return CACHE_PATH.read
      end

      Rails.logger.info 'Downloading fresh CSV from Dhan…'
      csv_text = URI.open(CSV_URL, &:read) # rubocop:disable Security/Open

      CACHE_PATH.dirname.mkpath
      File.write(CACHE_PATH, csv_text)
      Rails.logger.info "Saved CSV to #{CACHE_PATH}"

      csv_text
    rescue StandardError => e
      Rails.logger.warn "CSV download failed: #{e.message}"
      raise e if CACHE_PATH.exist? == false   # don’t swallow if no fallback

      Rails.logger.warn 'Falling back to cached CSV (may be stale)'
      CACHE_PATH.read
    end
    private :fetch_csv_with_cache             # keep helper private

    def import_from_csv(csv_content)
      instruments_rows, derivatives_rows = build_batches(csv_content)
      Rails.logger.debug do
        "instrument rows: #{instruments_rows.size}; derivative rows: #{derivatives_rows.size}"
      end
      # instruments_rows.uniq!  { |r| r.values_at(:security_id, :symbol_name, :exchange, :segment) }
      # derivatives_rows.uniq!  { |r| r.values_at(:security_id, :symbol_name, :exchange, :segment) }

      instrument_import = instruments_rows.empty? ? nil : import_instruments!(instruments_rows)
      derivative_import = derivatives_rows.empty? ? nil : import_derivatives!(derivatives_rows)

      {
        instrument_rows: instruments_rows.size,
        derivative_rows: derivatives_rows.size,
        instrument_upserts: instrument_import&.ids&.size.to_i,
        derivative_upserts: derivative_import&.ids&.size.to_i,
        instrument_total: Instrument.count,
        derivative_total: Derivative.count
      }
    end

    private

    # ------------------------------------------------------------
    # 1. Split CSV rows
    # ------------------------------------------------------------
    def build_batches(csv_content)
      instruments = []
      derivatives = []

      CSV.parse(csv_content, headers: true).each do |row|
        next unless VALID_EXCHANGES.include?(row['EXCH_ID'])

        attrs = build_attrs(row)

        if row['SEGMENT'] == 'D'   # Derivative
          derivatives << attrs.slice(*Derivative.column_names.map(&:to_sym))
        else                       # Cash / Index
          instruments << attrs.slice(*Instrument.column_names.map(&:to_sym))
        end
      end

      [instruments, derivatives]
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
    # 3. Upsert instruments
    # ------------------------------------------------------------
    def import_instruments!(rows)
      Instrument.import(
        rows,
        batch_size: BATCH_SIZE,
        on_duplicate_key_update: {
          conflict_target: %i[security_id symbol_name exchange segment],
          columns: %i[
            display_name isin instrument_code instrument_type
            underlying_symbol lot_size tick_size updated_at
          ]
        }
      ).tap do |res|
        Rails.logger.info "Upserted Instruments: #{res.ids.size}"
      end
    end

    # ------------------------------------------------------------
    # 4. Upsert derivatives
    # ------------------------------------------------------------
    def import_derivatives!(rows)
      with_parent, without_parent = attach_instrument_ids(rows)

      Rails.logger.info "Derivatives w/ parent: #{with_parent.size}"
      Rails.logger.info "Derivatives w/o parent: #{without_parent.size}"

      return if with_parent.empty?

      Derivative.import(
        with_parent,
        batch_size: BATCH_SIZE,
        on_duplicate_key_update: {
          conflict_target: %i[security_id symbol_name exchange segment],
          columns: %i[
            symbol_name display_name isin instrument_code instrument_type
            underlying_symbol series lot_size tick_size updated_at
          ]
        }
      ).tap do |res|
        Rails.logger.info "Upserted Derivatives: #{res.ids.size}"
      end
    end

    # ------------------------------------------------------------
    # 4a. Attach instrument_id to each derivative row
    # ------------------------------------------------------------
    def attach_instrument_ids(rows)
      enum_to_csv = Instrument.instrument_codes

      # 🔑 lookup key = [csv_code, UNDERLYING_SYMBOL]
      lookup = Instrument.pluck(
        :id, :instrument_code, :underlying_symbol, :exchange, :segment
      ).each_with_object({}) do |(id, enum_code, sym, _exch, _seg), h|
        next if sym.blank?

        csv_code = enum_to_csv[enum_code] || enum_code # keep CSV code itself
        key      = [csv_code, sym.upcase]
        h[key]   = id
      end

      Rails.logger.debug { "lookup size: #{lookup.size}" }

      with_parent    = []
      without_parent = []
      count = 0
      rows.each do |h|
        count += 1 if h[:underlying_symbol]
        next without_parent << h if h[:underlying_symbol].blank?

        parent_code = InstrumentTypeMapping.underlying_for(h[:instrument_code]) # FUTIDX ➜ INDEX
        key         = [parent_code, h[:underlying_symbol].upcase]

        if (pid = lookup[key])
          h[:instrument_id] = pid
          with_parent << h
        else
          without_parent << h
        end
      end

      [with_parent, without_parent]
    end

    # ------------------------------------------------------------
    # Helpers
    # ------------------------------------------------------------
    def safe_date(str)
      Date.parse(str)
    rescue StandardError
      nil
    end

    def map_segment(char)
      { 'I' => 'index', 'E' => 'equity', 'C' => 'currency',
        'D' => 'derivatives', 'M' => 'commodity' }[char] || char.downcase
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
