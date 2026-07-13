# frozen_string_literal: true

require_relative "indicators/primitives"
require_relative "indicators/super_trend2"
require_relative "indicators/dmi"

# SuperTrend2 Options Signal Generator
#
# Direct port of the Pine Script indicator:
#   "SuperTrend2 Options Strategy Dashboard + ADX Filter"
#
# Input:  Array of OHLCV bars (from DhanHQ or CSV)
# Output: Array of signal hashes — one per bar
#
# Signal values:
#   "BUY CALLS"         — enter call option
#   "BUY PUTS"          — enter put option
#   "BOOK CALL PROFITS" — exit calls
#   "BOOK PUT PROFITS"  — exit puts
#   "HOLD"              — no action
#
# Each output hash also contains all intermediate indicator values
# so you can inspect why a signal fired.
class SuperTrendSignalGenerator
  # ── Pine Script defaults ────────────────────────────────────────
  DEFAULT_CONFIG = {
    # SuperTrend2
    st_factor:     2.0,
    use_wicks:     true,
    dynamic_atr:   true,

    # RSI
    rsi_length:    14,

    # Volatility
    atr_length:           14,
    vol_threshold_lookback: 20,
    atr_expansion_bars:   10,

    # ADX
    use_adx_filter: true,
    adx_length:     14,
    adx_smoothing:  14,
    dir_confirm:    true,

    # Timeframe in minutes — drives dynamic thresholds
    # Set this to match the candle interval of your data
    tf_minutes: 5
  }.freeze

  def initialize(config = {})
    @cfg = DEFAULT_CONFIG.merge(config)
    derive_dynamic_thresholds
  end

  # @param bars [Array<Hash>] :open, :high, :low, :close, :volume
  # @return [Array<Hash>] one result per bar (first N bars are nil during warm-up)
  def generate(bars)
    return [] if bars.empty?

    # ── Step 1: compute base ATR (for dynamic length + volatility regime) ──
    base_atr_values = Indicators::ATR.new(length: @cfg[:atr_length]).calculate(bars)

    # ── Step 2: dynamic ATR length per bar (Pine: dynAtrLen) ──────────────
    closes      = bars.map { |b| b[:close] }
    rsi_values  = Indicators::RSI.new(length: @cfg[:rsi_length]).calculate(closes)
    vol_sma20   = Indicators::SMA.calculate(bars.map { |b| b[:volume] }, 20)

    dyn_atr_lengths = bars.size.times.map do |i|
      atr_adj = if @cfg[:dynamic_atr] && rsi_values[i] && vol_sma20[i]
                  vol_spike = bars[i][:volume] > vol_sma20[i] * 1.2
                  rsi = rsi_values[i]
                  rsi > 60 ? 3 : vol_spike ? 2 : 0
                else
                  0
                end
      @st_atr_base + atr_adj
    end

    # ── Step 3: recompute ATR per bar using its dynamic length ────────────
    # Pine computes a single dynAtrLen per bar then passes to supertrend2.
    # We approximate by computing ATR with each unique length and mapping.
    # For typical use (length varies 8–13) this is equivalent.
    atr_cache = {}
    dyn_atr_per_bar = bars.size.times.map do |i|
      len = dyn_atr_lengths[i]
      unless atr_cache[len]
        atr_cache[len] = Indicators::ATR.new(length: len).calculate(bars)
      end
      atr_cache[len][i]
    end

    # ── Step 4: SuperTrend2 using per-bar dynamic ATR ─────────────────────
    bars_with_atr = bars.each_with_index.map do |bar, i|
      bar.merge(atr: atr_per_bar_or_fallback(atr_per_bar: dyn_atr_per_bar, base_atr: base_atr_values, i: i))
    end

    st2_results = Indicators::SuperTrend2.new(
      factor:    @cfg[:st_factor],
      use_wicks: @cfg[:use_wicks]
    ).calculate(bars_with_atr)

    # ── Step 5: ATR volatility regime ─────────────────────────────────────
    atr_pcts        = base_atr_values.map.with_index { |atr, i| atr ? (atr / bars[i][:close]) * 100 : nil }
    avg_atr_pct     = Indicators::SMA.calculate(atr_pcts.map { |v| v || 0 }, @cfg[:vol_threshold_lookback])
    atr_sma_exp     = Indicators::SMA.calculate(base_atr_values.map { |v| v || 0 }, @cfg[:atr_expansion_bars])

    # ── Step 6: ADX/DMI ───────────────────────────────────────────────────
    dmi_results = Indicators::DMI.new(
      length:    @cfg[:adx_length],
      smoothing: @cfg[:adx_smoothing]
    ).calculate(bars)

    # ── Step 7: assemble signal per bar ───────────────────────────────────
    open_position = nil

    bars.size.times.map do |i|
      bar      = bars[i]
      st       = st2_results[i]
      dmi      = dmi_results[i] || {}
      rsi      = rsi_values[i]
      atr_val  = base_atr_values[i]
      atr_pct  = atr_pcts[i]
      avg_atr  = avg_atr_pct[i]
      atr_sma  = atr_sma_exp[i]

      next build_warmup(bar, i) if rsi.nil? || atr_val.nil? || avg_atr.nil? || dmi[:adx].nil?

      # Volatility thresholds (dynamic, same as Pine)
      vol_med_thresh  = avg_atr * 0.90
      vol_high_thresh = avg_atr * 1.10

      # ATR regime
      atr_rising   = atr_val >= atr_sma * 1.02
      atr_declining = atr_val <= atr_sma * 0.95

      # Volatility gate
      volatility_ok = atr_rising && atr_pct >= vol_med_thresh

      # SuperTrend state
      st_bullish    = st[:direction] == -1
      st_bearish    = st[:direction] == 1
      st_flip_bull  = i > 0 && st2_results[i - 1][:direction] == 1  && st[:direction] == -1
      st_flip_bear  = i > 0 && st2_results[i - 1][:direction] == -1 && st[:direction] == 1

      # Wick/close cross (mirrors Pine long_wick_entry / short_wick_entry)
      prev = i > 0 ? bars[i - 1] : nil
      long_wick_entry  = prev && (@cfg[:use_wicks] ? ta_crossover_high(bar, prev, st[:st]) : ta_crossover_close(bar, prev, st[:st]))
      short_wick_entry = prev && (@cfg[:use_wicks] ? ta_crossunder_low(bar, prev, st[:st]) : ta_crossunder_close(bar, prev, st[:st]))

      # RSI gates (dynamic thresholds)
      call_rsi_ok = rsi > @rsi_buy_min  && rsi < @rsi_buy_max
      put_rsi_ok  = rsi > @rsi_sell_min && rsi < @rsi_sell_max

      # ADX gates
      adx        = dmi[:adx]
      diplus     = dmi[:diplus]
      diminus    = dmi[:diminus]
      adx_ok     = adx >= @disinterest_level
      adx_strong = adx >= @trend_level
      adx_gate   = !@cfg[:use_adx_filter] || adx_ok
      di_bull    = diplus  > diminus
      di_bear    = diminus > diplus
      call_dir_ok = !@dir_confirm || di_bull
      put_dir_ok  = !@dir_confirm || di_bear

      # ── Final entry conditions ──────────────────────────────────────
      call_buy_candidate = long_wick_entry  && call_rsi_ok && volatility_ok && st_bullish && adx_gate && call_dir_ok
      put_buy_candidate  = short_wick_entry && put_rsi_ok  && volatility_ok && st_bearish && adx_gate && put_dir_ok

      # ── Profit booking conditions ───────────────────────────────────
      profit_book_call_candidate = st_flip_bear || rsi > @rsi_buy_max  || atr_declining || (@cfg[:use_adx_filter] && !adx_ok)
      profit_book_put_candidate  = st_flip_bull || rsi < @rsi_sell_max || atr_declining || (@cfg[:use_adx_filter] && !adx_ok)

      call_buy = call_buy_candidate && open_position.nil?
      put_buy = put_buy_candidate && open_position.nil?
      profit_book_call = profit_book_call_candidate && open_position == :calls
      profit_book_put = profit_book_put_candidate && open_position == :puts

      # ── Signal ─────────────────────────────────────────────────────
      signal = if call_buy
                 "BUY CALLS"
               elsif put_buy
                 "BUY PUTS"
               elsif profit_book_call
                 "BOOK CALL PROFITS"
               elsif profit_book_put
                 "BOOK PUT PROFITS"
               else
                 "HOLD"
               end

      open_position = next_position_state(open_position, signal)

      # Position sizing suggestion
      position_size = if atr_pct > vol_high_thresh
                        "Large"
                      elsif atr_pct > vol_med_thresh
                        "Medium"
                      else
                        "Small"
                      end

      strike_distance = (bar[:close] * (atr_pct / 100) * 1.5).round
      market_mode     = compute_market_mode(adx_strong, adx_ok, atr_rising, atr_declining, atr_pct, vol_med_thresh)

      {
        bar_index:       i,
        timestamp:       bar[:timestamp],
        close:           bar[:close].round(2),
        signal:          signal,
        # Indicator values (for diagnostics)
        rsi:             rsi.round(2),
        atr_pct:         atr_pct.round(4),
        atr_rising:      atr_rising,
        atr_declining:   atr_declining,
        volatility_ok:   volatility_ok,
        vol_med_thresh:  vol_med_thresh.round(4),
        vol_high_thresh: vol_high_thresh.round(4),
        st_value:        st[:st].round(4),
        st_direction:    st[:direction],
        st_bullish:      st_bullish,
        st_flip_bull:    st_flip_bull,
        st_flip_bear:    st_flip_bear,
        adx:             adx.round(2),
        diplus:          diplus.round(2),
        diminus:         diminus.round(2),
        adx_ok:          adx_ok,
        adx_strong:      adx_strong,
        call_rsi_ok:     call_rsi_ok,
        put_rsi_ok:      put_rsi_ok,
        call_buy:        call_buy,
        put_buy:         put_buy,
        profit_book_call: profit_book_call,
        profit_book_put:  profit_book_put,
        market_mode:     market_mode,
        position_size:   position_size,
        strike_distance: strike_distance
      }
    end.compact
  end

  private

  def derive_dynamic_thresholds
    tf = @cfg[:tf_minutes]

    # Direct port of Pine dynamic threshold blocks
    @st_atr_base      = tf <= 1 ? 8  : tf <= 15 ? 9  : 10
    @rsi_buy_min      = tf <= 1 ? 30 : tf <= 15 ? 35 : 40
    @rsi_buy_max      = tf <= 1 ? 80 : tf <= 15 ? 75 : 70
    @rsi_sell_min     = tf <= 1 ? 20 : tf <= 15 ? 25 : 30
    @rsi_sell_max     = tf <= 1 ? 70 : tf <= 15 ? 65 : 60
    @disinterest_level = tf <= 1 ? 12 : tf <= 15 ? 15 : 20
    @trend_level      = tf <= 1 ? 20 : tf <= 15 ? 28 : 35
    @dir_confirm      = tf >= 15
  end

  def atr_per_bar_or_fallback(atr_per_bar:, base_atr:, i:)
    atr_per_bar[i] || base_atr[i] || 0.0
  end

  # Pine ta.crossover for HIGH (wick mode): high > st2 and prev_high <= prev_st2
  # Approximation: we use the current ST value for both bars since ST updates each bar
  def ta_crossover_high(bar, prev_bar, st_val)
    bar[:high] > st_val && prev_bar[:high] <= st_val
  end

  # Pine ta.crossunder for LOW (wick mode)
  def ta_crossunder_low(bar, prev_bar, st_val)
    bar[:low] < st_val && prev_bar[:low] >= st_val
  end

  # Pine ta.crossover close mode
  def ta_crossover_close(bar, prev_bar, st_val)
    bar[:close] > st_val && prev_bar[:close] <= st_val
  end

  # Pine ta.crossunder close mode
  def ta_crossunder_close(bar, prev_bar, st_val)
    bar[:close] < st_val && prev_bar[:close] >= st_val
  end

  def compute_market_mode(adx_strong, adx_ok, atr_rising, atr_declining, atr_pct, vol_med_thresh)
    if @cfg[:use_adx_filter]
      if adx_strong && atr_rising
        "BUY MODE"
      elsif !adx_ok || atr_declining
        "HOLD/SELL MODE"
      else
        "NEUTRAL"
      end
    else
      if atr_rising && atr_pct > vol_med_thresh
        "BUY MODE"
      elsif atr_declining || atr_pct < vol_med_thresh
        "HOLD/SELL MODE"
      else
        "NEUTRAL"
      end
    end
  end

  def build_warmup(bar, i)
    { bar_index: i, timestamp: bar[:timestamp], close: bar[:close], signal: nil, warmup: true }
  end

  def next_position_state(current_position, signal)
    case signal
    when "BUY CALLS"
      :calls
    when "BUY PUTS"
      :puts
    when "BOOK CALL PROFITS", "BOOK PUT PROFITS"
      nil
    else
      current_position
    end
  end
end