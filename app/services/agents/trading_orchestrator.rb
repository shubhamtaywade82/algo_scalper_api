# frozen_string_literal: true

module Agents
  # Chains MarketAnalyst → Strategy → Risk → OptionSelector in sequence.
  # All market data, strike selection and order routing remain deterministic.
  # The LLM only performs reasoning on pre-computed indicator/SMC data.
  #
  # Usage:
  #   result = Agents::TradingOrchestrator.call(index_key: "NIFTY")
  #   # => { action:, entered:, telegram_sent:, ... }
  class TradingOrchestrator
    TAG = "[Agents::TradingOrchestrator]"

    DIRECTION_MAP = {
      "BUY_CALL" => :bullish,
      "BUY_PUT"  => :bearish
    }.freeze

    def self.call(index_key:, interval: "5")
      new(index_key: index_key.to_s.upcase, interval: interval).call
    end

    def initialize(index_key:, interval:)
      @index_key = index_key
      @interval  = interval
    end

    def call
      log "Starting pipeline for #{@index_key}"

      index_cfg = resolve_index_cfg
      return abort("No index config for #{@index_key}") unless index_cfg

      # ── Stage 1: Market Analysis ──────────────────────────────────────────
      analyst_result = run_agent("MarketAnalystAgent") do
        MarketAnalystAgent.call(index_key: @index_key, interval: @interval)
      end
      return abort("MarketAnalystAgent failed: #{analyst_result[:error]}") if analyst_result[:error]

      analysis = analyst_result[:content]

      # ── Stage 2: Strategy ─────────────────────────────────────────────────
      strategy_result = run_agent("StrategyAgent") do
        StrategyAgent.call(
          index_key:       @index_key,
          market_analysis: format_for_prompt(analysis)
        )
      end
      return abort("StrategyAgent failed: #{strategy_result[:error]}") if strategy_result[:error]

      strategy = strategy_result[:content]
      action   = extract_action(strategy)

      if action == "NO_TRADE"
        msg = format_no_trade_message(analysis, strategy)
        notify_telegram(msg)
        log "NO_TRADE — pipeline complete"
        return result(action: "NO_TRADE", entered: false, telegram_sent: true, analysis: analysis, strategy: strategy)
      end

      # ── Stage 3: Risk ─────────────────────────────────────────────────────
      risk_result = run_agent("RiskAgent") do
        RiskAgent.call(strategy_details: format_for_prompt(strategy))
      end
      return abort("RiskAgent failed: #{risk_result[:error]}") if risk_result[:error]

      risk    = risk_result[:content]
      verdict = extract_verdict(risk)

      if verdict == "REJECTED"
        msg = format_rejected_message(analysis, strategy, risk)
        notify_telegram(msg)
        log "REJECTED by risk agent"
        return result(action: action, entered: false, telegram_sent: true, analysis: analysis, strategy: strategy, risk: risk)
      end

      # ── Stage 4: Option Selection ─────────────────────────────────────────
      direction = DIRECTION_MAP.fetch(action, :bullish)

      selector_result = run_agent("OptionSelectorAgent") do
        OptionSelectorAgent.call(index_key: @index_key, direction: direction.to_s)
      end
      return abort("OptionSelectorAgent failed: #{selector_result[:error]}") if selector_result[:error]

      selection = selector_result[:content]

      # ── Pick Hash — resolved deterministically via ChainAnalyzer ──────────
      picks = Options::ChainAnalyzer.pick_strikes(index_cfg: index_cfg, direction: direction)
      if picks.blank?
        msg = format_no_strikes_message(analysis, strategy, selection)
        notify_telegram(msg)
        return result(action: action, entered: false, telegram_sent: true, reason: "no_strikes_from_chain")
      end

      # Prefer the pick matching the agent's recommended strike if available
      agent_strike  = extract_strike(selection)
      pick          = picks.min_by { |p| (p[:strike].to_f - agent_strike.to_f).abs }

      # ── Stage 5: Entry ────────────────────────────────────────────────────
      size_multiplier = extract_size_multiplier(risk)

      entered = Entries::EntryGuard.try_enter(
        index_cfg:       index_cfg,
        pick:            pick,
        direction:       direction,
        scale_multiplier: size_multiplier,
        entry_metadata:  {
          entry_contract:   Entries::EntryGuard::SUPERTREND_CONTRACT,
          permission:       :scale_ready,
          ai_orchestrated:  true,
          agent_action:     action,
          agent_rationale:  extract_rationale(strategy)
        }
      )

      msg = format_entry_message(analysis, strategy, risk, selection, pick, entered)
      notify_telegram(msg)

      log "Pipeline complete — entered=#{entered}"
      result(
        action:   action,
        entered:  entered,
        telegram_sent: true,
        analysis: analysis,
        strategy: strategy,
        risk:     risk,
        selection: selection,
        pick:     pick
      )
    rescue StandardError => e
      Rails.logger.error("#{TAG} Unhandled error: #{e.class} - #{e.message}\n#{e.backtrace.first(8).join("\n")}")
      { error: e.message, entered: false }
    end

    private

    # ── Index Config ──────────────────────────────────────────────────────────

    def resolve_index_cfg
      IndexConfigLoader.load_indices.find { |c| c[:key].to_s.upcase == @index_key }
    end

    # ── Agent Runner ──────────────────────────────────────────────────────────

    def run_agent(name)
      r = yield
      if r.error?
        log "#{name} returned error: #{r.error_message}"
        { error: r.error_message }
      else
        log "#{name} OK (#{r.input_tokens}in/#{r.output_tokens}out)"
        { content: r.content }
      end
    rescue StandardError => e
      log "#{name} raised: #{e.class} - #{e.message}"
      { error: e.message }
    end

    # ── Helpers ───────────────────────────────────────────────────────────────

    def format_for_prompt(value)
      return value.to_json.truncate(600) if value.is_a?(Hash)

      value.to_s.truncate(600)
    end

    # Extracts BUY_CALL / BUY_PUT / NO_TRADE from a Hash or free-text LLM response.
    def extract_action(content)
      if content.is_a?(Hash)
        val = (content[:action] || content["action"]).to_s.upcase
        return val if %w[BUY_CALL BUY_PUT NO_TRADE].include?(val)
      end
      text = content.to_s.upcase
      return "NO_TRADE" if text.match?(/\bNO[_\s]TRADE\b/)
      return "BUY_CALL" if text.match?(/\bBUY[_\s]CALL\b/)
      return "BUY_PUT"  if text.match?(/\bBUY[_\s]PUT\b/)

      # Infer from directional language if no explicit keyword found
      return "BUY_PUT"  if text.match?(/\b(BEARISH|SHORT|PUT)\b/) && !text.match?(/\bNEUTRAL\b/)
      return "BUY_CALL" if text.match?(/\b(BULLISH|LONG|CALL)\b/) && !text.match?(/\bNEUTRAL\b/)

      "NO_TRADE"
    end

    # Extracts APPROVED / REJECTED from a Hash or free-text risk response.
    # Defaults to APPROVED so a narrative risk response doesn't silently block entry.
    def extract_verdict(content)
      if content.is_a?(Hash)
        val = (content[:verdict] || content["verdict"]).to_s.upcase
        return val if %w[APPROVED REJECTED].include?(val)
      end
      text = content.to_s.upcase
      return "REJECTED" if text.match?(/\bREJECTED\b/)

      "APPROVED"
    end

    def extract_strike(selection)
      if selection.is_a?(Hash)
        return (selection[:strike] || selection["strike"]).to_f
      end
      # Try to find a 5-digit number in narrative (e.g. "24400")
      m = selection.to_s.match(/\b(\d{4,6}(?:\.\d+)?)\b/)
      m ? m[1].to_f : 0.0
    end

    def extract_size_multiplier(risk)
      if risk.is_a?(Hash)
        m = (risk[:position_size_multiplier] || risk["position_size_multiplier"]).to_f
        return m.clamp(0.25, 1.0) if m.positive?
      end
      1.0
    end

    def extract_rationale(strategy)
      return (strategy[:rationale] || strategy["rationale"]).to_s if strategy.is_a?(Hash)

      # Pull last 200 chars of narrative as rationale
      strategy.to_s.strip.split("\n").reject(&:blank?).last(3).join(" ").truncate(300)
    end

    # ── Telegram Messages ─────────────────────────────────────────────────────

    def notify_telegram(message)
      Notifications::TelegramNotifier.instance.send_message(message)
    rescue StandardError => e
      log "Telegram notify failed: #{e.message}"
    end

    def format_no_trade_message(analysis, strategy)
      bias     = dig(analysis, :bias, "N/A")
      strength = dig(analysis, :trend_strength, "N/A")
      rationale = dig(strategy, :rationale, dig(strategy.to_s, nil, strategy.to_s.truncate(200)))

      <<~HTML.strip
        🤖 <b>AI Signal — #{@index_key}</b>
        📊 Bias: #{bias} | Strength: #{strength}
        🚫 <b>Action: NO TRADE</b>

        <i>#{rationale}</i>
      HTML
    end

    def format_rejected_message(analysis, strategy, risk)
      bias   = dig(analysis, :bias, "N/A")
      action = dig(strategy, :action, "?")
      notes  = dig(risk, :notes, "Risk limits exceeded")

      <<~HTML.strip
        🤖 <b>AI Signal — #{@index_key}</b>
        📊 Bias: #{bias}
        ⚠️ <b>Action: #{action} — RISK REJECTED</b>

        <i>#{notes}</i>
      HTML
    end

    def format_no_strikes_message(analysis, strategy, selection)
      bias   = dig(analysis, :bias, "N/A")
      action = dig(strategy, :action, "?")

      <<~HTML.strip
        🤖 <b>AI Signal — #{@index_key}</b>
        📊 Bias: #{bias} | Action: #{action}
        ❌ <b>No valid strikes from option chain</b>

        Agent suggested: #{dig(selection, :selected_contract, "unknown")} @ #{dig(selection, :premium, "?")}
        Market may be outside normal range.
      HTML
    end

    def format_entry_message(analysis, strategy, risk, selection, pick, entered)
      bias     = dig(analysis, :bias, "N/A")
      strength = dig(analysis, :trend_strength, "N/A")
      zones    = dig(analysis, :key_zones, "—")
      action   = dig(strategy, :action, "?")
      trigger  = dig(strategy, :entry_trigger, "—")
      sl       = dig(strategy, :stop_loss, "—")
      tp       = dig(strategy, :take_profit, "—")
      hold     = dig(strategy, :max_holding_time, "—")
      trailing = dig(strategy, :trailing_rules, "—")
      rationale = dig(strategy, :rationale, "—")
      verdict  = dig(risk, :verdict, "?")
      max_risk = dig(risk, :max_risk_rupees, "?")
      size_pct = (extract_size_multiplier(risk) * 100).round

      symbol   = pick[:symbol]
      ltp      = pick[:ltp].to_f.round(2)
      strike   = pick[:strike].to_f.round(0).to_i

      status_icon = entered ? "✅" : "❌"
      status_text = entered ? "ORDER PLACED" : "ENTRY BLOCKED BY GUARDS"

      <<~HTML.strip
        🤖 <b>AI Trading Signal — #{@index_key}</b>

        📊 <b>Analysis</b>
        Bias: #{bias} | Strength: #{strength}
        Key Zones: #{zones.to_s.truncate(120)}

        🎯 <b>Strategy: #{action}</b>
        Entry Trigger: #{trigger.to_s.truncate(100)}
        SL: #{sl} | TP: #{tp}
        Max Hold: #{hold}
        Trailing: #{trailing.to_s.truncate(80)}

        📋 <b>Selected Contract</b>
        Symbol: #{symbol}
        Strike: #{strike} | LTP: ₹#{ltp}

        🛡️ <b>Risk</b>
        Verdict: #{verdict} | Size: #{size_pct}% | Max Risk: ₹#{max_risk}

        #{status_icon} <b>#{status_text}</b>

        <i>#{rationale.to_s.truncate(200)}</i>
      HTML
    end

    # Agent stages usually return free-text markdown, not a Hash — for the
    # fields we headline in Telegram (bias/action/verdict), fall back to the
    # same text extraction already used to drive control flow instead of
    # silently showing a placeholder that contradicts the body text below it.
    def dig(obj, key, default = nil)
      if obj.is_a?(Hash)
        val = obj[key] || obj[key.to_s]
        return val if val
      end
      extract_from_text(obj, key) || default
    end

    def extract_from_text(obj, key)
      return nil if obj.is_a?(Hash)

      case key
      when :bias
        obj.to_s[/\b(BULLISH|BEARISH|NEUTRAL)\b/i]&.upcase
      when :trend_strength
        obj.to_s[/\bADX\D{0,5}(\d+(?:\.\d+)?)/i, 1]&.then { |v| "ADX #{v}" }
      when :action
        extract_action(obj)
      when :verdict
        extract_verdict(obj)
      end
    end

    def log(msg)
      Rails.logger.info("#{TAG} #{msg}")
    end

    def abort(reason)
      log "Aborted: #{reason}"
      { error: reason, entered: false }
    end

    def result(**attrs)
      { entered: false }.merge(attrs)
    end
  end
end
