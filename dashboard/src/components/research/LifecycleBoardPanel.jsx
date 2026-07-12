import { createSignal, onMount, For, Show } from 'solid-js'
import { Table, TableHeader, TableBody, TableRow, TableHead, TableCell } from '../ui/Table'
import Badge from '../ui/Badge'
import Button from '../ui/Button'
import Select from '../ui/Select'
import Input from '../ui/Input'
import PremiumChart from './PremiumChart'

const SYMBOLS = [
  { value: 'NIFTY', label: 'NIFTY' },
  { value: 'BANKNIFTY', label: 'BANKNIFTY' },
  { value: 'SENSEX', label: 'SENSEX' }
]
const EXPIRY_FLAGS = [
  { value: 'WEEK', label: 'Weekly' },
  { value: 'MONTH', label: 'Monthly' }
]

function statusVariant(status) {
  switch (status) {
    case 'computed': return 'success'
    case 'no_data': return 'outline'
    case 'failed': return 'danger'
    default: return 'outline'
  }
}

function fmtPct(v) {
  if (v === null || v === undefined) return '—'
  return `${v >= 0 ? '+' : ''}${v.toFixed(2)}%`
}

function fmtTime(v) {
  if (!v) return '—'
  return new Date(v).toLocaleString('en-IN', { day: '2-digit', month: 'short', hour: '2-digit', minute: '2-digit', hour12: false })
}

const CONTEXT_FIELDS = [
  { key: 'close', label: 'Underlying' },
  { key: 'atr', label: 'ATR (14)' },
  { key: 'adx', label: 'ADX (14)' },
  { key: 'rsi', label: 'RSI (14)' },
  { key: 'vwap', label: 'VWAP' },
  { key: 'vwap_distance', label: 'VWAP Dist.' }
]

const REGIME_FIELDS = [
  { key: 'market_structure', label: 'Structure' },
  { key: 'trend', label: 'Trend' },
  { key: 'volatility_regime', label: 'Volatility' },
  { key: 'momentum', label: 'Momentum' },
  { key: 'volume_regime', label: 'Volume' },
  { key: 'vwap_relation', label: 'VWAP' },
  { key: 'liquidity_sweep', label: 'Liquidity' },
  { key: 'opening_range_breakout', label: 'ORB' },
  { key: 'gap', label: 'Gap' },
  { key: 'time_context', label: 'Session' }
]

function regimeLabel(value) {
  if (!value || value === 'unknown') return '—'
  return String(value).replace(/_/g, ' ')
}

export default function LifecycleBoardPanel() {
  const [symbol, setSymbol] = createSignal('NIFTY')
  const [date, setDate] = createSignal('')
  const [spotPrice, setSpotPrice] = createSignal('')
  const [expiryFlag, setExpiryFlag] = createSignal('WEEK')
  const [maxDistance, setMaxDistance] = createSignal('5')
  const [entryTime, setEntryTime] = createSignal('09:15')

  const [running, setRunning] = createSignal(false)
  const [error, setError] = createSignal(null)
  const [ranked, setRanked] = createSignal([])

  const [detail, setDetail] = createSignal(null)
  const [bars, setBars] = createSignal([])
  const [detailLoading, setDetailLoading] = createSignal(false)

  const [history, setHistory] = createSignal([])

  async function fetchHistory() {
    try {
      const res = await fetch('/api/research/lifecycles?per_page=10')
      const data = await res.json()
      setHistory(data.lifecycles || [])
    } catch {
      // best-effort
    }
  }

  onMount(fetchHistory)

  async function runBoard(e) {
    e.preventDefault()
    setError(null)
    setRunning(true)
    setDetail(null)
    try {
      const res = await fetch('/api/research/lifecycles/run', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          underlying_symbol: symbol(),
          date: date(),
          spot_price: spotPrice(),
          expiry_flag: expiryFlag(),
          max_distance: maxDistance(),
          entry_time: entryTime()
        })
      })
      const data = await res.json()
      if (!res.ok) throw new Error(data.error || `HTTP ${res.status}`)
      setRanked(data.lifecycles || [])
      fetchHistory()
    } catch (err) {
      setError(err.message)
    } finally {
      setRunning(false)
    }
  }

  async function loadDetail(id) {
    setDetailLoading(true)
    setError(null)
    try {
      const res = await fetch(`/api/research/lifecycles/${id}`)
      const data = await res.json()
      if (!res.ok) throw new Error(data.error || `HTTP ${res.status}`)
      setDetail(data.lifecycle)
      setBars(data.bars || [])
    } catch (err) {
      setError(err.message)
    } finally {
      setDetailLoading(false)
    }
  }

  return (
    <div class="flex flex-col gap-6">
      <form onSubmit={runBoard} class="glass rounded-2xl border border-white/5 px-6 py-5">
        <div class="flex flex-wrap items-end gap-4">
          <div class="w-36">
            <Select label="Symbol" value={symbol()} onChange={(e) => setSymbol(e.target.value)} options={SYMBOLS} />
          </div>
          <div class="w-40">
            <Input label="Session Date" type="date" value={date()} onInput={(e) => setDate(e.target.value)} />
          </div>
          <div class="w-32">
            <Input label="Spot Price" type="number" step="0.01" value={spotPrice()} onInput={(e) => setSpotPrice(e.target.value)} />
          </div>
          <div class="w-32">
            <Select label="Expiry" value={expiryFlag()} onChange={(e) => setExpiryFlag(e.target.value)} options={EXPIRY_FLAGS} />
          </div>
          <div class="w-28">
            <Input label="Max ± Strikes" type="number" min="0" max="10" value={maxDistance()} onInput={(e) => setMaxDistance(e.target.value)} />
          </div>
          <div class="w-28">
            <Input label="Entry Time" type="time" value={entryTime()} onInput={(e) => setEntryTime(e.target.value)} />
          </div>
          <Button type="submit" loading={running()} disabled={!date() || !spotPrice()}>
            Run Board
          </Button>
        </div>
        <p class="text-[10px] text-gray-600 mt-2">
          Fetches CE + PE across ATM±N strikes from DhanHQ (up to {2 * Number(maxDistance() || 0) + 2} real API calls) — this can take a little while.
        </p>
        <Show when={error()}>
          <div class="text-rose-400 text-xs mt-2">⚠ {error()}</div>
        </Show>
      </form>

      <Show when={ranked().length > 0}>
        <div class="glass rounded-2xl border border-white/5 px-6 py-4">
          <h3 class="text-xs font-black text-white uppercase tracking-widest mb-4">Strike Comparison — ranked by peak return</h3>
          <div class="overflow-x-auto">
            <Table>
              <TableHeader>
                <TableRow class="bg-white/[0.02]">
                  <TableHead class="p-3 text-[10px] font-black text-gray-500 uppercase">Strike</TableHead>
                  <TableHead class="p-3 text-[10px] font-black text-gray-500 uppercase">Type</TableHead>
                  <TableHead class="p-3 text-[10px] font-black text-gray-500 uppercase">Status</TableHead>
                  <TableHead class="p-3 text-[10px] font-black text-gray-500 uppercase text-right">Peak Return</TableHead>
                  <TableHead class="p-3 text-[10px] font-black text-gray-500 uppercase text-right">Time to Peak</TableHead>
                  <TableHead class="p-3 text-[10px] font-black text-gray-500 uppercase text-right">Max Drawdown</TableHead>
                  <TableHead class="p-3 text-[10px] font-black text-gray-500 uppercase text-right">End Return</TableHead>
                </TableRow>
              </TableHeader>
              <TableBody class="divide-y divide-white/5">
                <For each={ranked()}>
                  {(l) => (
                    <TableRow class="hover:bg-white/[0.03] cursor-pointer" onClick={() => loadDetail(l.id)}>
                      <TableCell class="p-3 text-sm font-bold text-white">{l.strike_label}</TableCell>
                      <TableCell class="p-3"><Badge variant={l.option_type === 'CE' ? 'success' : 'danger'} class="text-[10px]">{l.option_type}</Badge></TableCell>
                      <TableCell class="p-3"><Badge variant={statusVariant(l.status)} class="text-[10px] uppercase">{l.status}</Badge></TableCell>
                      <TableCell class={`p-3 text-right text-xs font-bold ${l.peak_return_pct >= 0 ? 'text-emerald-400' : 'text-rose-400'}`}>{fmtPct(l.peak_return_pct)}</TableCell>
                      <TableCell class="p-3 text-right text-xs text-gray-300">{l.minutes_to_peak ?? '—'} min</TableCell>
                      <TableCell class="p-3 text-right text-xs text-rose-400">{fmtPct(l.max_drawdown_after_peak_pct)}</TableCell>
                      <TableCell class="p-3 text-right text-xs text-gray-300">{fmtPct(l.end_return_pct)}</TableCell>
                    </TableRow>
                  )}
                </For>
              </TableBody>
            </Table>
          </div>
        </div>
      </Show>

      <Show when={detailLoading()}>
        <div class="text-xs text-gray-600 uppercase text-center py-6">Loading lifecycle detail...</div>
      </Show>

      <Show when={detail() && !detailLoading()}>
        <div class="glass rounded-2xl border border-white/5 px-6 py-4">
          <div class="flex items-center justify-between mb-4">
            <h3 class="text-xs font-black text-white uppercase tracking-widest">
              {detail().underlying_symbol} {detail().option_type} {detail().strike_label} — {fmtTime(detail().entry_ts)}
            </h3>
            <div class="flex gap-4 text-[10px] font-black text-gray-500 uppercase tracking-widest">
              <span>Peak <span class="text-emerald-400">{fmtPct(detail().peak_return_pct)}</span></span>
              <span>Time to Peak <span class="text-white">{detail().minutes_to_peak} min</span></span>
              <span>Max DD <span class="text-rose-400">{fmtPct(detail().max_drawdown_after_peak_pct)}</span></span>
            </div>
          </div>

          <PremiumChart bars={bars} peakPremium={() => detail().peak_premium} height={320} />

          <div class="grid grid-cols-2 gap-4 mt-4">
            <For each={['entry', 'peak']}>
              {(phase) => (
                <div class="rounded-xl border border-white/5 p-4">
                  <h4 class="text-[10px] font-black text-gray-500 uppercase tracking-widest mb-2">Underlying at {phase}</h4>
                  <Show
                    when={detail().underlying_context?.[phase] && Object.keys(detail().underlying_context[phase]).length > 0}
                    fallback={<span class="text-xs text-gray-600">Not enough underlying history to compute</span>}
                  >
                    <div class="grid grid-cols-2 gap-y-1.5">
                      <For each={CONTEXT_FIELDS}>
                        {(f) => (
                          <>
                            <span class="text-[10px] text-gray-500 uppercase">{f.label}</span>
                            <span class="text-xs text-gray-200 text-right">
                              {detail().underlying_context[phase][f.key] !== null && detail().underlying_context[phase][f.key] !== undefined
                                ? Number(detail().underlying_context[phase][f.key]).toFixed(2)
                                : '—'}
                            </span>
                          </>
                        )}
                      </For>
                    </div>

                    <Show when={detail().underlying_context[phase].regime}>
                      <div class="mt-3 pt-3 border-t border-white/5 flex flex-wrap gap-1.5">
                        <For each={REGIME_FIELDS}>
                          {(f) => (
                            <Show when={detail().underlying_context[phase].regime[f.key] && detail().underlying_context[phase].regime[f.key] !== 'unknown'}>
                              <Badge variant="outline" class="text-[9px] uppercase tracking-wide" title={f.label}>
                                {f.label}: {regimeLabel(detail().underlying_context[phase].regime[f.key])}
                              </Badge>
                            </Show>
                          )}
                        </For>
                      </div>
                    </Show>
                  </Show>
                </div>
              )}
            </For>
          </div>
        </div>
      </Show>

      <div class="glass rounded-2xl border border-white/5 px-6 py-4">
        <h3 class="text-xs font-black text-gray-400 uppercase tracking-widest mb-3">Recent Lifecycles</h3>
        <div class="flex flex-col divide-y divide-white/5">
          <For each={history()}>
            {(l) => (
              <button
                onClick={() => loadDetail(l.id)}
                class="flex items-center justify-between py-2.5 text-left hover:bg-white/[0.03] px-2 rounded transition-colors"
              >
                <span class="text-xs font-bold text-gray-300">{l.underlying_symbol} {l.option_type} {l.strike_label} · {fmtTime(l.entry_ts)}</span>
                <span class={`text-[10px] font-bold uppercase ${l.peak_return_pct >= 0 ? 'text-emerald-400' : 'text-rose-400'}`}>{fmtPct(l.peak_return_pct)}</span>
              </button>
            )}
          </For>
          <Show when={history().length === 0}>
            <div class="py-6 text-center text-gray-600 text-xs uppercase">No lifecycles yet — run the board above</div>
          </Show>
        </div>
      </div>
    </div>
  )
}
