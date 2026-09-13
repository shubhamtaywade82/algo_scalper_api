# frozen_string_literal: true

module Ledger
  class EntryPoster
    # Deterministic outcome of booking a paper entry. Never `nil`.
    #
    #   posted    journal committed
    #   duplicate idempotency-key replay (already booked)
    #   rejected  paper account cannot afford the entry (InsufficientCash)
    #   failed    unexpected error — logged + stamped on the tracker so the
    #             state is queryable instead of silently swallowed
    #   disabled  paper posting switched off for this tracker/config
    class Result
      STATUSES = %i[posted duplicate rejected failed disabled].freeze

      attr_reader :status, :journal, :error

      def initialize(status:, journal: nil, error: nil)
        @status = status
        @journal = journal
        @error = error
      end

      STATUSES.each do |status|
        define_method(:"#{status}?") { @status == status }
      end

      def success?
        posted? || duplicate?
      end

      def to_s
        "Ledger::EntryPoster::Result(#{status}#{": #{error}" if error})"
      end
    end

    class << self
      # @return [Result] always a Result — callers branch on status instead of
      #   checking nil. Previously this returned nil on every failure path,
      #   leaving no deterministic state behind (review finding #16).
      def post!(tracker:, fill_price:, quantity:, order_no: nil)
        return Result.new(status: :disabled) unless paper_posting?(tracker)
        return Result.new(status: :disabled) unless Config.posting_enabled_for_paper?

        Seeder.ensure_ready!

        qty = quantity.to_i
        price = BigDecimal(fill_price.to_s)
        gross = (qty * price).round(2)
        fee = BrokerFeeCalculator.fee_per_order

        journal = PostingService.post!(
          idempotency_key: "entry:#{tracker.id}",
          event_type: 'entry_fill',
          mode: :paper,
          position_tracker_id: tracker.id,
          order_no: order_no || tracker.order_no,
          trading_date: Time.zone.today,
          meta: {
            symbol: tracker.symbol,
            security_id: tracker.security_id,
            gross_premium: gross.to_f,
            fee: fee.to_f,
            iv_percentile: tracker.iv_percentile
          }.compact,
          lines: entry_lines(tracker: tracker, gross: gross, fee: fee)
        )

        stamp_tracker!(tracker, 'posted')
        Result.new(status: :posted, journal: journal)
      rescue PostingService::InsufficientCashError => e
        # Deterministic domain outcome: the paper account can't afford this
        # entry. Surface it on the tracker so it is queryable, not just a log
        # line that disappears.
        Rails.logger.warn("[Ledger::EntryPoster] REJECTED (insufficient cash) tracker=#{tracker.id}: #{e.message}")
        stamp_tracker!(tracker, 'rejected', e.message)
        Result.new(status: :rejected, error: e.message)
      rescue StandardError => e
        # Unexpected failure: keep it loud AND persisted. No silent nil.
        Rails.logger.error("[Ledger::EntryPoster] FAILED #{e.class} - #{e.message} tracker=#{tracker.id}")
        Rails.error.report(e, handled: true, context: { component: 'Ledger::EntryPoster', tracker_id: tracker.id }) if Rails.respond_to?(:error)
        stamp_tracker!(tracker, 'failed', "#{e.class}: #{e.message}")
        Result.new(status: :failed, error: "#{e.class}: #{e.message}")
      end

      # Long: pay cash for the option (an asset you hold, "premium_deployed").
      # Short: receive cash for writing the option (a liability, "premium_written"),
      # and separately lock margin as collateral out of free cash ("margin_blocked").
      def entry_lines(tracker:, gross:, fee:)
        base = [
          { account_code: 'brokerage_expense', debit: fee },
          { account_code: 'cash', credit: fee }
        ]

        if tracker.short_position?
          margin = BigDecimal(tracker.margin_required.to_s)
          base + [
            { account_code: 'cash', debit: gross },
            { account_code: 'premium_written', credit: gross },
            { account_code: 'margin_blocked', debit: margin },
            { account_code: 'cash', credit: margin }
          ]
        else
          base + [
            { account_code: 'premium_deployed', debit: gross },
            { account_code: 'cash', credit: gross }
          ]
        end
      end

      # Paper-posting gate. A config document that cannot be READ used to be
      # reported as "posting disabled" (rescue -> false) — conflating "off"
      # with "unknown". Config failures now propagate as
      # Errors::ConfigurationError and surface through the :failed Result of
      # #post! (stamped on the tracker), never as a silent skip.
      def paper_posting?(tracker)
        return true if tracker.paper?

        AlgoConfig.paper_trading_enabled?
      end

      private

      # Stamps the ledger outcome into tracker meta (queryable state) without
      # firing the full callback stack — meta is not part of any index.
      def stamp_tracker!(tracker, status, error = nil)
        meta = (tracker.meta.is_a?(Hash) ? tracker.meta.dup : {})
        meta['ledger_status'] = status
        meta['ledger_error'] = error if error
        meta['ledger_stamped_at'] = Time.current.iso8601
        tracker.update_columns(meta: meta, updated_at: Time.current)
      rescue StandardError => e
        Rails.logger.warn("[Ledger::EntryPoster] could not stamp tracker=#{tracker.id}: #{e.message}")
      end
    end
  end
end
