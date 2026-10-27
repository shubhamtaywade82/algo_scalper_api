# frozen_string_literal: true

module Reports
  module MarketBrief
    # Turns consecutive Market Brief snapshots into discrete market events.
    #
    # Pure with respect to I/O: it only compares snapshot hashes (string keys, as
    # produced by SnapshotBuilder) and keeps the previous snapshot plus the side of
    # each price level in memory. The watcher owns the schedule, persistence and
    # LLM triggering; nothing here calls the broker, the LLM or the database.
    #
    # Level crosses use a hysteresis band (LEVEL_BUFFER around each level): price has
    # to close beyond the band on the far side, and the side is remembered, so
    # chop around a swing point produces one event per genuine cross, not one per tick.
    #
    # A cross is only reported between two decided sides. A level first observed
    # inside its band has no side yet, so its first decided side is recorded silently.
    # That is the price of avoiding false crosses: a level that appears on an SMC
    # refresh with price already beyond it must not fire.
    #
    # A level is identified by its label and price, so a level that moves on the
    # next SMC refresh starts a fresh side memory instead of firing a false cross.
    class EventDetector
      LEVEL_BUFFER = 0.0005 # 0.05% band around a level
      LOSS_THRESHOLDS = [50, 80, 100].freeze # % of daily loss limit
      UNKNOWN_VALUES = [nil, 'UNAVAILABLE', 'NO_DATA', 'unavailable'].freeze
      TIMEFRAMES = %w[htf mtf ltf].freeze

      # Events that change what the commentary should say. Feed, quote and
      # data-state events are shown on the page but do not start an LLM run.
      AI_TRIGGER_KINDS = %w[
        session_opened regime_changed smc_decision_changed bias_agreement_changed
        level_crossed vix_gate_changed circuit_breaker_changed setup_decision_changed
        candidate_appeared positions_changed loss_threshold_crossed
      ].freeze

      attr_reader :previous

      def initialize
        reset!
      end

      # Forgets the previous snapshot and every remembered level side. Called when
      # the session is not open, so the next open session starts from a clean baseline.
      def reset!
        @previous = nil
        @level_sides = {}
      end

      # @param snapshot [Hash] SnapshotBuilder output (string keys)
      # @return [Array<Hash>] events observed between the previous and this snapshot
      def detect(snapshot)
        now = snapshot['generated_at']
        status = snapshot.dig('session', 'status')

        unless status == 'open'
          was_open = @previous&.dig('session', 'status') == 'open'
          reset!
          return was_open ? [event('session_closed', now, message: 'Cash session closed')] : []
        end

        prior = @previous
        @previous = snapshot
        return bootstrap(snapshot, now) if prior.nil?

        index_events(prior, snapshot, now) + global_events(prior, snapshot, now)
      end

      def self.ai_trigger?(event)
        AI_TRIGGER_KINDS.include?(event['kind'])
      end

      private

      # First observed open snapshot: announce the open and seed level sides without
      # emitting crosses, so the price at which the watcher starts is not an event.
      def bootstrap(snapshot, now)
        Array(snapshot['indices']).each { |idx| levels_for(idx).each { |lvl| observe_side(idx, lvl) } }
        [event('session_opened', now, message: 'Market open: opening brief')]
      end

      def index_events(prior, current, now)
        Array(current['indices']).flat_map do |idx|
          key = idx['index_key']
          before = Array(prior['indices']).find { |i| i['index_key'] == key } || {}

          [
            state_change(now, 'regime_changed', key, before.dig('regime', 'label'), idx.dig('regime', 'label'),
                         ->(f, t) { "#{key} regime #{f} → #{t}" }),
            state_change(now, 'smc_decision_changed', key, before.dig('smc', 'decision'), idx.dig('smc', 'decision'),
                         ->(f, t) { "#{key} SMC decision #{f} → #{t}" }),
            state_change(now, 'bias_agreement_changed', key, before.dig('bias', 'agreement'), idx.dig('bias', 'agreement'),
                         ->(f, t) { "#{key} technical vs SMC #{f} → #{t}" }),
            quote_state_change(now, key, before.dig('quote', 'status'), idx.dig('quote', 'status'))
          ].compact + level_events(now, key, idx)
        end
      end

      def level_events(now, key, idx)
        ltp = idx.dig('quote', 'ltp')
        return [] unless ltp.is_a?(Numeric)

        levels_for(idx).filter_map do |lvl|
          previous_side, current_side = observe_side(idx, lvl, ltp: ltp)
          next if previous_side.nil? || current_side.nil? || previous_side == current_side

          direction = current_side == :above ? 'upward' : 'downward'
          event('level_crossed', now,
                index_key: key, label: lvl[:label], price: lvl[:price], ltp: ltp.to_f, direction: direction,
                message: format('%<key>s crossed %<label>s %<price>.2f %<dir>s (LTP %<ltp>.2f)',
                                key: key, label: lvl[:label], price: lvl[:price], dir: direction, ltp: ltp.to_f))
        end
      end

      # Records which side of a level the price is on and returns [previous, current].
      # Price inside the hysteresis band decides nothing, so the last decided side
      # is kept and nil is returned.
      def observe_side(idx, lvl, ltp: idx.dig('quote', 'ltp'))
        return nil unless ltp.is_a?(Numeric)

        memory_key = "#{idx['index_key']}|#{lvl[:label]}|#{lvl[:price]}"
        side = side_of(ltp.to_f, lvl[:price])
        return nil if side == :inside

        previous = @level_sides[memory_key]
        @level_sides[memory_key] = side
        [previous, side]
      end

      def side_of(ltp, price)
        if ltp > price * (1 + LEVEL_BUFFER) then :above
        elsif ltp < price * (1 - LEVEL_BUFFER) then :below
        else :inside
        end
      end

      def levels_for(idx)
        frames = idx.dig('smc', 'timeframes') || {}
        TIMEFRAMES.flat_map do |tf|
          frame = frames[tf] || {}
          tag = tf.upcase
          [
            { label: "#{tag} swing high", price: frame['swing_high'] },
            { label: "#{tag} swing low", price: frame['swing_low'] },
            { label: "#{tag} BOS", price: frame.dig('last_bos', 'price') }
          ].select { |lvl| lvl[:price].is_a?(Numeric) && lvl[:price].positive? }
        end
      end

      def quote_state_change(now, key, from, to)
        return nil if from.nil? || to.nil? || from == to

        event('quote_state_changed', now, index_key: key, from: from, to: to,
                                          message: "#{key} quote #{from} → #{to}")
      end

      def global_events(prior, current, now)
        [
          state_change(now, 'vix_gate_changed', nil, gate_label(prior), gate_label(current),
                       ->(f, t) { "India VIX entry gate #{f} → #{t}" }),
          state_change(now, 'circuit_breaker_changed', nil, breaker_label(prior), breaker_label(current),
                       ->(f, t) { "Circuit breaker #{f} → #{t}" }),
          state_change(now, 'feed_state_changed', nil, feed_label(prior), feed_label(current),
                       ->(f, t) { "Market feed #{f} → #{t}" }),
          state_change(now, 'setup_decision_changed', nil, prior.dig('setup', 'decision'), current.dig('setup', 'decision'),
                       ->(f, t) { "Setup decision #{f} → #{t}" }),
          candidate_event(prior, current, now),
          positions_event(prior, current, now)
        ].compact + loss_events(prior, current, now)
      end

      def candidate_event(prior, current, now)
        to = current.dig('setup', 'candidate', 'signal_id')
        from = prior.dig('setup', 'candidate', 'signal_id')
        return nil if to.nil? || to == from

        cand = current.dig('setup', 'candidate')
        event('candidate_appeared', now, index_key: cand['index_key'], signal_id: to,
                                         message: "Approved candidate: #{cand['index_key']} #{cand['option_type']} (signal ##{to})")
      end

      def positions_event(prior, current, now)
        from = prior.dig('risk', 'active_positions_count')
        to = current.dig('risk', 'active_positions_count')
        return nil if from.nil? || to.nil? || from == to

        event('positions_changed', now, from: from, to: to, message: "Active positions #{from} → #{to}")
      end

      def loss_events(prior, current, now)
        before = prior.dig('risk', 'daily_loss', 'utilization_pct')
        after = current.dig('risk', 'daily_loss', 'utilization_pct')
        return [] unless before.is_a?(Numeric) && after.is_a?(Numeric)

        LOSS_THRESHOLDS.select { |t| before < t && after >= t }.map do |t|
          event('loss_threshold_crossed', now, threshold: t, to: after.to_f.round(1),
                                               message: "Daily loss limit used crossed #{t}% (now #{after.to_f.round(1)}%)")
        end
      end

      def state_change(now, kind, index_key, from, to, describe)
        return nil unless known?(from) && known?(to) && from != to

        event(kind, now, index_key: index_key, from: from, to: to, message: describe.call(from, to))
      end

      def known?(value)
        UNKNOWN_VALUES.exclude?(value)
      end

      def gate_label(snapshot)
        vix = snapshot.dig('market_context', 'vix') || {}
        return nil if vix['entry_allowed'].nil?

        vix['entry_allowed'] ? 'ALLOWS entries' : 'BLOCKS entries'
      end

      def breaker_label(snapshot)
        tripped = snapshot.dig('risk', 'circuit_breaker', 'tripped')
        return nil if tripped.nil?

        tripped ? 'TRIPPED' : 'armed'
      end

      def feed_label(snapshot)
        status = snapshot.dig('health', 'components', 'market_feed', 'status')
        status&.upcase
      end

      def event(kind, at, **attrs)
        { 'kind' => kind, 'at' => at, 'ai_trigger' => AI_TRIGGER_KINDS.include?(kind) }
          .merge(attrs.transform_keys(&:to_s))
      end
    end
  end
end
