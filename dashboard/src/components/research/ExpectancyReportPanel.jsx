import { createSignal, For, Show } from 'solid-js'
import { Table, TableHeader, TableBody, TableRow, TableHead, TableCell } from '../ui/Table'
import Badge from '../ui/Badge'
import Button from '../ui/Button'
import Select from '../ui/Select'
import Input from '../ui/Input'

const ALL_DIMENSIONS = [
  { key: 'market_structure', label: 'Structure' },
  { key: 'trend', label: 'Trend' },
  { key: 'volatility_regime', label: 'Volatility' },
  { key: 'momentum', label: 'Momentum' },
  { key: 'volume_regime', label: 'Volume' },
  { key: 'time_context', label: 'Session' },
  { key: 'vwap_relation', label: 'VWAP' },
  { key: 'liquidity_sweep', label: 'Liquidity' },
  { key: 'opening_range_breakout', label: 'ORB' },
  { key: 'gap', label: 'Gap' }
]
const DEFAULT_DIMENSIONS = ['trend', 'opening_range_breakout', 'volatility_regime']

const SYMBOLS = [
  { value: '', label: 'All' },
  { value: 'NIFTY', label: 'NIFTY' },
  { value: 'BANKNIFTY', label: 'BANKNIFTY' },
  { value: 'SENSEX', label: 'SENSEX' }
]
const OPTION_TYPES = [
  { value: '', label: 'All' },
  { value: 'CE', label: 'CE' },
  { value: 'PE', label: 'PE' }
]
const PHASES = [
  { value: 'entry', label: 'At entry' },
  { value: 'peak', label: 'At peak' }
]

function fmtPct(v) {
  if (v === null || v === undefined) return '—'
  return `${v >= 0 ? '+' : ''}${v.toFixed(2)}%`
}

export default function ExpectancyReportPanel() {
  const [symbol, setSymbol] = createSignal('')
  const [optionType, setOptionType] = createSignal('')
  const [dateFrom, setDateFrom] = createSignal('')
  const [dateTo, setDateTo] = createSignal('')
  const [phase, setPhase] = createSignal('entry')
  const [dimensions, setDimensions] = createSignal(DEFAULT_DIMENSIONS)

  const [loading, setLoading] = createSignal(false)
  const [error, setError] = createSignal(null)
  const [buckets, setBuckets] = createSignal([])
  const [totalLifecycles, setTotalLifecycles] = createSignal(null)

  function toggleDimension(key) {
    setDimensions((current) => (
      current.includes(key) ? current.filter((d) => d !== key) : [...current, key]
    ))
  }

  async function runReport(e) {
    e.preventDefault()
    setError(null)
    if (dimensions().length === 0) {
      setError('Select at least one context dimension')
      return
    }
    setLoading(true)
    try {
      const params = new URLSearchParams()
      if (symbol()) params.set('underlying_symbol', symbol())
      if (optionType()) params.set('option_type', optionType())
      if (dateFrom()) params.set('date_from', dateFrom())
      if (dateTo()) params.set('date_to', dateTo())
      params.set('phase', phase())
      params.set('dimensions', dimensions().join(','))

      const res = await fetch(`/api/research/lifecycles/expectancy?${params.toString()}`)
      const data = await res.json()
      if (!res.ok) throw new Error(data.error || `HTTP ${res.status}`)
      setBuckets(data.buckets || [])
      setTotalLifecycles(data.total_lifecycles ?? null)
    } catch (err) {
      setError(err.message)
    } finally {
      setLoading(false)
    }
  }

  return (
    <div class="flex flex-col gap-6">
      <form onSubmit={runReport} class="glass rounded-2xl border border-white/5 px-6 py-5">
        <div class="flex flex-wrap items-end gap-4">
          <div class="w-36">
            <Select label="Symbol" value={symbol()} onChange={(e) => setSymbol(e.target.value)} options={SYMBOLS} />
          </div>
          <div class="w-28">
            <Select label="Option Type" value={optionType()} onChange={(e) => setOptionType(e.target.value)} options={OPTION_TYPES} />
          </div>
          <div class="w-40">
            <Input label="From" type="date" value={dateFrom()} onInput={(e) => setDateFrom(e.target.value)} />
          </div>
          <div class="w-40">
            <Input label="To" type="date" value={dateTo()} onInput={(e) => setDateTo(e.target.value)} />
          </div>
          <div class="w-36">
            <Select label="Phase" value={phase()} onChange={(e) => setPhase(e.target.value)} options={PHASES} />
          </div>
          <Button type="submit" loading={loading()}>Run Report</Button>
        </div>

        <div class="mt-4">
          <label class="block text-[10px] font-black text-gray-500 uppercase tracking-widest mb-2">
            Group by context dimensions
          </label>
          <div class="flex flex-wrap gap-2">
            <For each={ALL_DIMENSIONS}>
              {(dim) => (
                <button
                  type="button"
                  onClick={() => toggleDimension(dim.key)}
                  class={`px-3 py-1.5 rounded-full text-[10px] font-black uppercase tracking-wide border transition-colors ${
                    dimensions().includes(dim.key)
                      ? 'bg-cyan-700/40 border-cyan-500/40 text-cyan-200'
                      : 'bg-transparent border-white/10 text-gray-500 hover:text-gray-300'
                  }`}
                >
                  {dim.label}
                </button>
              )}
            </For>
          </div>
        </div>

        <Show when={error()}>
          <div class="text-rose-400 text-xs mt-3">⚠ {error()}</div>
        </Show>
      </form>

      <Show when={buckets().length > 0}>
        <div class="glass rounded-2xl border border-white/5 px-6 py-4">
          <div class="flex items-center justify-between mb-4">
            <h3 class="text-xs font-black text-white uppercase tracking-widest">Context → Expectancy Map</h3>
            <span class="text-[10px] font-bold text-gray-500 uppercase tracking-tighter">
              {totalLifecycles()} lifecycles analyzed
            </span>
          </div>
          <div class="overflow-x-auto">
            <Table>
              <TableHeader>
                <TableRow class="bg-white/[0.02]">
                  <TableHead class="p-3 text-[10px] font-black text-gray-500 uppercase">Context</TableHead>
                  <TableHead class="p-3 text-[10px] font-black text-gray-500 uppercase text-right">Sample</TableHead>
                  <TableHead class="p-3 text-[10px] font-black text-gray-500 uppercase text-right">Avg Peak Return</TableHead>
                  <TableHead class="p-3 text-[10px] font-black text-gray-500 uppercase text-right">Win Rate</TableHead>
                  <TableHead class="p-3 text-[10px] font-black text-gray-500 uppercase text-right">Avg Time to Peak</TableHead>
                  <TableHead class="p-3 text-[10px] font-black text-gray-500 uppercase text-right">Avg Drawdown</TableHead>
                  <TableHead class="p-3 text-[10px] font-black text-gray-500 uppercase text-right">Avg End Return</TableHead>
                </TableRow>
              </TableHeader>
              <TableBody class="divide-y divide-white/5">
                <For each={buckets()}>
                  {(b) => (
                    <TableRow class="hover:bg-white/[0.03]">
                      <TableCell class="p-3">
                        <div class="flex flex-wrap gap-1">
                          <For each={Object.entries(b.context)}>
                            {([key, value]) => (
                              <Badge variant={value === 'unknown' ? 'outline' : 'info'} class="text-[9px] uppercase">
                                {value === 'unknown' ? 'unknown' : String(value).replace(/_/g, ' ')}
                              </Badge>
                            )}
                          </For>
                        </div>
                      </TableCell>
                      <TableCell class="p-3 text-right text-xs text-gray-300">{b.sample_size}</TableCell>
                      <TableCell class={`p-3 text-right text-xs font-bold ${b.avg_return_pct >= 0 ? 'text-emerald-400' : 'text-rose-400'}`}>{fmtPct(b.avg_return_pct)}</TableCell>
                      <TableCell class="p-3 text-right text-xs text-gray-200">{b.win_rate_pct !== null ? `${b.win_rate_pct.toFixed(1)}%` : '—'}</TableCell>
                      <TableCell class="p-3 text-right text-xs text-gray-300">{b.avg_time_to_peak_minutes !== null ? `${b.avg_time_to_peak_minutes.toFixed(0)} min` : '—'}</TableCell>
                      <TableCell class="p-3 text-right text-xs text-rose-400">{fmtPct(b.avg_drawdown_pct)}</TableCell>
                      <TableCell class="p-3 text-right text-xs text-gray-300">{fmtPct(b.avg_end_return_pct)}</TableCell>
                    </TableRow>
                  )}
                </For>
              </TableBody>
            </Table>
          </div>
          <p class="text-[10px] text-gray-600 mt-3">
            Low sample-size buckets are noise, not signal — treat single-digit counts as a hypothesis to keep testing, not a conclusion.
          </p>
        </div>
      </Show>

      <Show when={buckets().length === 0 && totalLifecycles() !== null && !loading()}>
        <div class="glass rounded-2xl border border-white/5 px-6 py-10 text-center text-gray-600 text-xs uppercase">
          No context buckets found for these filters — run more Premium Lifecycle Board sessions first
        </div>
      </Show>
    </div>
  )
}
