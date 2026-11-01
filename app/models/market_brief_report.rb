# frozen_string_literal: true

# Persisted one-page Market Brief.
#
# Lifecycle (deterministic, forward-only):
#   pending → building → ready     (snapshot persisted; AI may still be pending)
#   pending → building → failed    (snapshot could not be built)
#
# AI lifecycle is independent of the report lifecycle so risk/market facts are
# never held hostage by a slow or failing model:
#   pending → completed | unavailable | invalid | disabled | skipped_market_closed
#
# Triggers: `manual` (dashboard button), `scheduled` (recurring 15-min refresh) and
# `event` (Reports::MarketBrief::Watcher, one per material market-state change, with
# the change descriptions stored in trigger_reasons).
class MarketBriefReport < ApplicationRecord
  SCHEMA_VERSION = 1

  STATUSES = %w[pending building ready failed].freeze
  AI_STATUSES = %w[pending completed unavailable invalid disabled skipped_market_closed].freeze
  TRIGGERS = %w[manual scheduled event].freeze
  MODES = %w[paper live].freeze

  # Manual refreshes inside the same slot reuse one report — bounds LLM spend
  # to one call per mode per slot no matter how often the button is pressed.
  MANUAL_SLOT_SECONDS = 5.minutes.to_i
  # Scheduled AI refreshes (recurring.yml, market hours) get one report per 15-min slot.
  SCHEDULED_SLOT_SECONDS = 15.minutes.to_i
  # Event runs are keyed per event (millisecond precision) so none is collapsed; the
  # watcher enforces the debounce and cap before it creates one.
  MAX_TRIGGER_REASONS = 6
  # A build that never left `building` (worker crash) may be retried after this.
  BUILDING_TIMEOUT = 10.minutes

  validates :report_key, presence: true, uniqueness: true
  validates :trading_date, presence: true
  validates :status, inclusion: { in: STATUSES }
  validates :ai_status, inclusion: { in: AI_STATUSES }
  validates :trigger, inclusion: { in: TRIGGERS }
  validates :mode, inclusion: { in: MODES }

  scope :for_mode, ->(mode) { where(mode: mode.to_s) }
  scope :ready, -> { where(status: 'ready') }
  scope :latest_first, -> { order(created_at: :desc, id: :desc) }

  class << self
    # Finds or creates the report for the slot covering +now+. Safe under
    # concurrent callers: the unique index on report_key decides the winner.
    #
    # @return [Array(MarketBriefReport, Boolean)] the report and whether this call created it
    def request!(mode:, trigger: 'manual', now: Time.current, reasons: [])
      key = report_key_for(mode: mode, trigger: trigger, now: now)
      existing = find_by(report_key: key)
      return [existing, false] if existing

      record = create!(
        report_key: key,
        trading_date: now.in_time_zone(TradingSession::Service::IST_TIMEZONE).to_date,
        mode: mode.to_s,
        trigger: trigger.to_s,
        trigger_reasons: Array(reasons).map { |r| r.to_s.truncate(240) }.first(MAX_TRIGGER_REASONS),
        status: 'pending',
        ai_status: 'pending',
        schema_version: SCHEMA_VERSION
      )
      [record, true]
    rescue ActiveRecord::RecordNotUnique
      [find_by!(report_key: key), false]
    end

    def report_key_for(mode:, trigger:, now:)
      ist = now.in_time_zone(TradingSession::Service::IST_TIMEZONE)
      slot = case trigger.to_s
             when 'scheduled' then "s#{(ist.to_i / SCHEDULED_SLOT_SECONDS) * SCHEDULED_SLOT_SECONDS}"
             # Each event must create its own row: the random suffix keeps keys unique
             # even when two events share a timestamp.
             when 'event' then "e#{(ist.to_f * 1000).to_i}-#{SecureRandom.hex(3)}"
             else "m#{(ist.to_i / MANUAL_SLOT_SECONDS) * MANUAL_SLOT_SECONDS}"
             end
      "#{ist.to_date.iso8601}:#{mode}:#{slot}"
    end

    def latest_ready(mode:)
      for_mode(mode).ready.latest_first.first
    end
  end

  # Atomically moves pending (or a stuck building row) to building. Returns
  # false when another worker already owns the build — the caller must stop.
  def claim_for_build!
    claimed = self.class.where(id: id)
                  .where('status = ? OR (status = ? AND updated_at < ?)', 'pending', 'building', BUILDING_TIMEOUT.ago)
                  .update_all(status: 'building', updated_at: Time.current) # rubocop:disable Rails/SkipsModelValidations -- atomic compare-and-set claim
    reload
    claimed == 1
  end

  def ready?
    status == 'ready'
  end

  def as_api_json
    {
      id: id,
      report_key: report_key,
      trading_date: trading_date&.iso8601,
      mode: mode,
      trigger: trigger,
      trigger_reasons: trigger_reasons,
      status: status,
      schema_version: schema_version,
      snapshot_generated_at: snapshot_generated_at&.iso8601,
      snapshot_digest: snapshot_digest,
      snapshot: snapshot.presence,
      ai: {
        status: ai_status,
        model: ai_model,
        generated_at: ai_generated_at&.iso8601,
        error: ai_error,
        analysis: ai_status == 'completed' ? ai_analysis : nil
      },
      error: error,
      created_at: created_at&.iso8601,
      updated_at: updated_at&.iso8601
    }
  end
end
