# frozen_string_literal: true

module Risk
  module Rules
    # Rule that triggers exits when the option contract's Implied Volatility (IV)
    # collapses significantly relative to the entry IV.
    class IvCollapseRule < BaseRule
      PRIORITY = 21

      def evaluate(context)
        return skip_result unless context.active?

        tracker = context.tracker
        entry_iv = tracker.iv_at_entry
        return no_action_result unless entry_iv&.to_f&.positive?

        current_iv_val = fetch_current_iv(context)
        return no_action_result unless current_iv_val&.to_f&.positive?

        entry_iv = entry_iv.to_f
        current_iv_val = current_iv_val.to_f

        # Calculate percentage drop in IV
        iv_drop_pct = (entry_iv - current_iv_val) / entry_iv

        threshold = iv_collapse_threshold(context)
        if iv_drop_pct >= threshold
          exit_result(
            reason: 'IV_COLLAPSE',
            metadata: {
              path: 'iv_collapse',
              entry_iv: entry_iv.round(2),
              current_iv: current_iv_val.round(2),
              iv_drop_pct: (iv_drop_pct * 100.0).round(2),
              threshold_pct: (threshold * 100.0).round(2)
            }
          )
        else
          no_action_result
        end
      end

      def enabled?(context = nil)
        return false unless context

        cfg = context.risk_config.dig(:time_overrides, :iv_collapse) ||
              context.risk_config[:iv_collapse] || {}
        cfg[:enabled] == true
      end

      private

      def iv_collapse_threshold(context)
        cfg = context.risk_config.dig(:time_overrides, :iv_collapse) ||
              context.risk_config[:iv_collapse] || {}
        (cfg[:collapse_threshold] || 0.15).to_f
      end

      def fetch_current_iv(context)
        tracker = context.tracker
        instrument = tracker.underlying_instrument
        return nil unless instrument

        expiry_date = tracker.expiry_date || tracker.watchable&.expiry_date
        return nil unless expiry_date

        # Fetch option chain from the underlying instrument (uses 2-minute cache)
        chain = instrument.fetch_option_chain(expiry_date)
        return nil unless chain && chain[:oc]

        strike_key = tracker.watchable&.strike_price.to_f.to_s
        option_type_key = tracker.watchable&.option_type.to_s.downcase

        leg = chain[:oc][strike_key]&.[](option_type_key)
        leg&.dig('implied_volatility')&.to_f
      end
    end
  end
end
