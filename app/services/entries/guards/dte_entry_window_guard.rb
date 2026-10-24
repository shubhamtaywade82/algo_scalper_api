# frozen_string_literal: true

module Entries
  module Guards
    # Blocks new entries after DTE-specific max_entry_time (e.g. 0-DTE after 12:30).
    class DteEntryWindowGuard
      include BaseGuard

      def self.call(context)
        return PASS unless enabled?

        index_cfg = context[:index_cfg] || {}
        pick = context[:pick] || {}
        dte = Trading::DteResolver.days_to_expiry(pick: pick, index_cfg: index_cfg)
        max_time = Trading::DteParameterResolver.max_entry_time(dte: dte)
        return PASS if max_time.blank?

        now_hhmm = Time.current.in_time_zone('Asia/Kolkata').strftime('%H:%M')
        return PASS if now_hhmm <= max_time.to_s

        { blocked: "DTE entry window closed for DTE=#{dte} (max #{max_time} IST)" }
      rescue Errors::Error => e
        # Domain failures block (fail-closed) — a corrupt config must not
        # quietly reopen the entry window.
        { blocked: "dte_entry_window_failed: #{e.class} - #{e.message}" }
      rescue StandardError => e
        Rails.logger.warn("[DteEntryWindowGuard] #{e.class} - #{e.message}")
        PASS
      end

      # Opt-in: risk.dte_parameters.enabled must be explicitly true (an absent
      # section used to be treated as enabled).
      def self.enabled?
        cfg = AlgoConfig.fetch.dig(:risk, :dte_parameters) || {}
        cfg[:enabled] == true
      end
    end
  end
end
