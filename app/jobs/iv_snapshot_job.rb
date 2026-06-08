# frozen_string_literal: true

class IvSnapshotJob < ApplicationJob
  queue_as :default

  # Map index names to their DhanHQ security IDs and segments
  INDEX_MAP = {
    'NIFTY' => { security_id: '13', segment: 'index' },
    'BANKNIFTY' => { security_id: '25', segment: 'index' },
    'SENSEX' => { security_id: '27', segment: 'index' }
  }.freeze

  # Mapping for strike step (interval) per index
  STRIKE_STEP = {
    'NIFTY' => 50,
    'BANKNIFTY' => 100,
    'SENSEX' => 100
  }.freeze

  def perform
    INDEX_MAP.each do |symbol, config|
      capture_iv_for(symbol, config)
    end
  end

  private

  def capture_iv_for(symbol, config)
    instrument = Instrument.find_by(security_id: config[:security_id], segment: config[:segment])
    unless instrument
      Rails.logger.warn "[IvSnapshotJob] Instrument not found for #{symbol}"
      return
    end

    chain = instrument.fetch_option_chain
    unless chain && chain[:oc]
      Rails.logger.warn "[IvSnapshotJob] Failed to fetch option chain for #{symbol}"
      return
    end

    ltp = chain[:last_price] || instrument.resolve_ltp(segment: instrument.exchange_segment, security_id: instrument.security_id)
    unless ltp
      Rails.logger.warn "[IvSnapshotJob] LTP not available for #{symbol}"
      return
    end

    atm = atm_strike(ltp, symbol)

    %w[ce pe].each do |type|
      leg = chain[:oc][atm.to_f.to_s]&.[](type)
      next unless leg && leg['implied_volatility']

      IvSnapshot.create!(
        index_key: symbol.downcase,
        snapshot_date: Time.zone.today,
        implied_volatility: leg['implied_volatility'],
        strike_price: atm,
        option_type: type.upcase,
        underlying_ltp: ltp
      )
    end

    Rails.logger.info "[IvSnapshotJob] Captured IV for #{symbol} at ATM #{atm}"
  rescue StandardError => e
    Rails.logger.error "[IvSnapshotJob] Error for #{symbol}: #{e.message}"
  end

  def atm_strike(ltp, symbol)
    step = STRIKE_STEP[symbol] || 50
    (ltp.to_f / step).round * step
  end
end
