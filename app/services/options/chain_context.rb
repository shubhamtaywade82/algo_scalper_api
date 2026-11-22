# frozen_string_literal: true

module Options
  # Computes the shared chain-context payload (contract `chain-context/1`,
  # contracts/schemas/chain-context-1.schema.json) from a ChainWatchService
  # snapshot. Pure computation, no I/O: the publisher owns Redis.
  #
  # The math deliberately mirrors options-trading-agent's
  # src/options/chainAnalyzer.ts (analyzePcr / findOiWalls / calculateStraddle /
  # computeSentiment, same thresholds and roundings) so that the agent's local
  # fallback and the Rails-published context agree whenever they see the same
  # chain. The agent keeps its own local computation as the fallback when this
  # snapshot is missing or stale; drift between the two implementations shows
  # up in the agent's CI as differing results for the same fixture.
  class ChainContext
    BIAS_THRESHOLD = 20 # score >= 20 -> BULLISH, <= -20 -> BEARISH, else NEUTRAL
    ATM_RADIUS_STEPS = 3 # strikes within 3 strike-steps of ATM count as "ATM"
    NEUTRAL_PCR = 1.0

    # snapshot: the ChainWatchService snapshot hash
    # ({ index_key:, spot:, atm_strike:, expiry:, legs:, chain_stale:, updated_at: }).
    # Returns nil when the snapshot cannot produce a context (no spot, no
    # legs, or the chain REST data is stale) - callers treat nil as "do not
    # publish", which lets the consumer's staleness window do its job.
    def self.from_snapshot(snapshot)
      return nil unless publishable?(snapshot)

      index_key = snapshot[:index_key]
      spot = snapshot[:spot].to_f
      legs = snapshot[:legs]
      expiry = snapshot[:expiry]

      strikes = legs.map { |l| l[:strike].to_f }.uniq.sort
      atm_strike = nearest_strike(spot, strikes)
      step = min_strike_step(strikes)
      window_strikes = leg_window(strikes, atm_strike, step)

      pcr_data = analyze_pcr(legs, atm_strike, step)
      walls = find_oi_walls(legs, spot)
      straddle_premium = calculate_straddle(legs, atm_strike)
      sentiment = compute_sentiment(pcr_data, walls)

      {
        'schema' => 'chain-context/1',
        'underlying' => index_key,
        'expiry' => expiry,
        'spot' => spot,
        'computed_at_ms' => (Time.current.to_f * 1000).floor,
        'source' => 'algo_scalper_api',
        'window_strikes' => window_strikes,
        'pcr' => pcr_data[:pcr],
        'atm_pcr' => pcr_data[:atm_pcr],
        'call_resistance' => wall_json(walls[:call_resistance]),
        'put_support' => wall_json(walls[:put_support]),
        'headroom_ce' => walls[:call_resistance][:distance],
        'headroom_pe' => walls[:put_support][:distance],
        'straddle_premium' => straddle_premium,
        'expected_range' => {
          'lower' => round1(atm_strike - straddle_premium),
          'upper' => round1(atm_strike + straddle_premium)
        },
        'sentiment_score' => sentiment[:score],
        'bias' => sentiment[:bias],
        'verdict' => sentiment[:verdict]
      }
    end

    class << self
      private

      # chain_stale means the REST chain poll failed this cycle: leg OI comes
      # only from WS ticks, which carry no OI change events reliably enough
      # for wall analytics. A stale chain would publish walls that look
      # identical every second; better to publish nothing and let the agent
      # fall back to its own fetch.
      def publishable?(snapshot)
        return false if snapshot.nil?
        return false unless snapshot[:spot].to_f.positive?
        return false if snapshot[:chain_stale]
        return false if snapshot[:legs].to_a.empty?

        snapshot[:expiry].to_s.match?(/\A\d{4}-\d{2}-\d{2}\z/)
      end

      # Half-width of the observed window, in strike-steps from ATM: how many
      # strikes above (and below) ATM the analytics actually covered.
      # ChainWatchService requests ATM +/-5; roll or partial data can make the
      # live window smaller. Reported in the payload so consumers can tell.
      def leg_window(strikes, atm_strike, step)
        return 1 if strikes.empty? || !step.positive?

        max_offset = strikes.map { |s| ((s - atm_strike).abs / step).ceil }.max
        max_offset.clamp(1, 100)
      end

      def nearest_strike(spot, strikes)
        strikes.min_by { |s| (s - spot).abs }
      end

      def min_strike_step(strikes)
        return 50 if strikes.length < 2

        steps = strikes.each_cons(2).map { |a, b| (b - a).abs }.reject(&:zero?)
        steps.empty? ? 50 : steps.min
      end

      # Mirrors analyzePcr: totals over the window, ATM band within
      # ATM_RADIUS_STEPS strike-steps of ATM.
      def analyze_pcr(legs, atm_strike, step)
        radius = step * ATM_RADIUS_STEPS

        call_oi = 0
        put_oi = 0
        atm_call_oi = 0
        atm_put_oi = 0
        call_volume = 0
        put_volume = 0

        legs.each do |leg|
          oi = leg[:oi].to_i
          volume = leg[:volume].to_i
          case leg[:type]
          when 'CE'
            call_oi += oi
            call_volume += volume
            atm_call_oi += oi if (leg[:strike].to_f - atm_strike).abs <= radius
          when 'PE'
            put_oi += oi
            put_volume += volume
            atm_put_oi += oi if (leg[:strike].to_f - atm_strike).abs <= radius
          end
        end

        pcr = call_oi.positive? ? round2(put_oi.to_f / call_oi) : NEUTRAL_PCR
        atm_pcr = atm_call_oi.positive? ? round2(atm_put_oi.to_f / atm_call_oi) : pcr
        { pcr: pcr, atm_pcr: atm_pcr, call_oi: call_oi, put_oi: put_oi,
          call_volume: call_volume, put_volume: put_volume }
      end

      # Mirrors findOiWalls: max-OI call strike and max-OI put strike. When a
      # side has no OI at all the wall degenerates to the spot with zero OI,
      # exactly like the agent's local computation.
      def find_oi_walls(legs, spot)
        max_call_strike = spot
        max_call_oi = 0
        max_put_strike = spot
        max_put_oi = 0

        legs.each do |leg|
          oi = leg[:oi].to_i
          next if oi.zero? # ties stay with the first strike seen, like the TS loop

          if leg[:type] == 'CE' && oi > max_call_oi
            max_call_oi = oi
            max_call_strike = leg[:strike].to_f
          elsif leg[:type] == 'PE' && oi > max_put_oi
            max_put_oi = oi
            max_put_strike = leg[:strike].to_f
          end
        end

        {
          call_resistance: { strike: max_call_strike, oi: max_call_oi, distance: round1(max_call_strike - spot) },
          put_support: { strike: max_put_strike, oi: max_put_oi, distance: round1(spot - max_put_strike) }
        }
      end

      # Mirrors calculateStraddle: mid when both bid/ask exist, LTP otherwise.
      def calculate_straddle(legs, atm_strike)
        atm_legs = legs.select { |l| l[:strike].to_f == atm_strike }
        call = atm_legs.find { |l| l[:type] == 'CE' }
        put = atm_legs.find { |l| l[:type] == 'PE' }
        return 0.0 if call.nil? || put.nil?

        round1(mid_price(call) + mid_price(put))
      end

      def mid_price(leg)
        bid = leg[:bid].to_f
        ask = leg[:ask].to_f
        return ((bid + ask) / 2.0) if bid.positive? && ask.positive?

        leg[:ltp].to_f
      end

      # Mirrors computeSentiment: same contributions, same clamp, same verdict
      # format. Kept in sync deliberately; see the class comment.
      def compute_sentiment(pcr_data, walls)
        score = 0
        pcr = pcr_data[:pcr]
        atm_pcr = pcr_data[:atm_pcr]

        if pcr >= 1.2
          score += 25
        elsif pcr >= 1.0
          score += 10
        elsif pcr <= 0.7
          score -= 25
        elsif pcr <= 0.9
          score -= 10
        end

        score += 20 if atm_pcr >= 1.2
        score -= 20 if atm_pcr <= 0.8

        call_dist = walls[:call_resistance][:distance]
        put_dist = walls[:put_support][:distance]

        if call_dist <= 0
          score += 20
        elsif call_dist > 50
          score += 15
        elsif call_dist < 15
          score -= 25
        end

        if put_dist <= 0
          score -= 20
        elsif put_dist > 50
          score -= 15
        elsif put_dist < 15
          score += 25
        end

        score += 15 if pcr_data[:call_volume] > pcr_data[:put_volume] * 1.3
        score -= 15 if pcr_data[:put_volume] > pcr_data[:call_volume] * 1.3

        score = score.clamp(-100, 100)
        bias = score >= BIAS_THRESHOLD ? 'BULLISH' : (score <= -BIAS_THRESHOLD ? 'BEARISH' : 'NEUTRAL')
        verdict = "#{bias} (score #{score.positive? ? '+' : ''}#{score}, PCR #{pcr}, ATM PCR #{atm_pcr})"
        { score: score, bias: bias, verdict: verdict }
      end

      def wall_json(wall)
        {
          'strike' => wall[:strike].to_f,
          'oi' => wall[:oi].to_i,
          'distance' => wall[:distance]
        }
      end

      def round1(v)
        v.to_f.round(1)
      end

      def round2(v)
        v.to_f.round(2)
      end
    end
  end
end
