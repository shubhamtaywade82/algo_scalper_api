import { createMemo } from 'solid-js'
import { For } from 'solid-js'
import { useDashboardContext } from '../context/DashboardContext'
import { expiryBadgeMeta } from '../lib/expiryBadge'
import Badge from '../components/ui/Badge'

export default function Strategies() {
  const { indices, config } = useDashboardContext()

  const riskParameters = createMemo(() => {
    const r = config()?.risk || {}
    const m = config()?.market_session || {}
    const trailingStatus = (r.trailing?.enabled && m.config?.allow_trailing !== false) ? 'ACTIVE' : 'OFF'
    return [
      { label: 'Profit Floor', value: r.profit_floor?.enabled ? `${r.profit_floor.lock_pct}%` : 'OFF' },
      { label: 'Trailing', value: trailingStatus }
    ]
  })

  const signalFilters = createMemo(() => {
    const s = config()?.signals || {}
    const t = config()?.trading_time_restrictions || {}
    const m = config()?.market_session || {}
    return [
      { label: 'ADX Filter', value: s.enable_adx_filter ? `MIN ${s.adx_min_strength || 15}` : 'OFF' },
      { label: 'Direction Gate', value: s.enable_direction_gate ? 'ACTIVE' : 'OFF' },
      { label: 'Runners', value: m.config?.allow_runners ? 'ALLOWED' : 'OFF' },
      { label: 'Session Blackout', value: t.enabled ? t.avoid_periods?.[0] || '10:00-12:30' : 'OFF' }
    ]
  })

  const indicesList = createMemo(() => {
    const val = indices()
    if (Array.isArray(val)) return val
    return Object.values(val).filter(i => i && i.key)
  })

  function expiryVariant(className) {
    if (className.includes('text-emerald')) return 'success'
    if (className.includes('text-red') || className.includes('text-rose')) return 'danger'
    if (className.includes('text-amber') || className.includes('text-yellow')) return 'warning'
    if (className.includes('text-blue') || className.includes('text-cyan')) return 'info'
    return 'outline'
  }

  return (
    <div class="space-y-6">
      <div class="flex items-center justify-between mb-2 px-2">
        <h2 class="text-sm font-black text-white uppercase tracking-widest flex items-center gap-2">
          <span class="w-2 h-2 rounded-full bg-primary-500" />
          Active Strategies
        </h2>
        <span class="text-[10px] font-bold text-gray-500 uppercase tracking-tighter">Live Config</span>
      </div>

      <div class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-6">
        <For each={indicesList()}>
          {(idx) => (
            <div class="glass glass-hover p-6 rounded-2xl flex flex-col gap-4 group overflow-hidden relative min-h-[160px]">
              <div class="absolute top-0 right-0 w-32 h-32 bg-primary-500/5 blur-3xl group-hover:bg-primary-500/10 transition-colors" />
              <div class="flex items-center justify-between relative z-10 gap-2">
                <div class="flex flex-col min-w-0">
                  <span class="text-xl font-black text-white tracking-tight">{idx.key}</span>
                  <span class="text-xs font-bold text-gray-500 uppercase tracking-widest mt-0.5">{idx.timeframe} Interval</span>
                  {(() => {
                    const b = expiryBadgeMeta(idx)
                    return (
                      <div class="flex flex-wrap items-center gap-1.5 mt-2">
                        <Badge
                          variant={expiryVariant(b.className)}
                          class="text-[9px] font-black uppercase tracking-tight"
                        >
                          {b.text}
                        </Badge>
                        <Show when={b.sub}>
                          <span class="text-[9px] font-bold text-gray-600">{b.sub}</span>
                        </Show>
                      </div>
                    )
                  })()}
                </div>
                <Badge variant="info" class="text-xs font-black uppercase tracking-tighter">
                  {idx.strategy}
                </Badge>
              </div>
              <div class="flex flex-col gap-2 mt-auto relative z-10">
                <div class="flex items-center justify-between text-[10px] font-bold uppercase tracking-widest text-gray-600">
                  <span>Status</span>
                  <span class="text-emerald-500">Scoping Index</span>
                </div>
                <div class="w-full bg-white/5 h-1 rounded-full overflow-hidden">
                  <div class="bg-primary-500 h-full w-2/3 animate-pulse" />
                </div>
              </div>
            </div>
          )}
        </For>
      </div>

      <div class="glass p-8 rounded-3xl mt-8">
        <h3 class="text-lg font-black text-white uppercase tracking-widest mb-4">Implementation Logic</h3>
        <div class="grid grid-cols-1 lg:grid-cols-2 gap-8">
          <div class="space-y-6">
            <p class="text-xs text-gray-400 leading-relaxed font-medium">
              The execution engine utilizes a multi-layered validation system. Primary entries are dictated by Supertrend flips on the 1-minute interval, while ADX strength scores and 5-minute HTF alignment act as critical gateways.
            </p>
            <div class="flex flex-wrap gap-4">
              <Badge variant="outline" class="px-4 py-2 rounded-xl">
                <span class="block text-[10px] font-black text-gray-600 uppercase tracking-widest mb-1">Entry Strategy</span>
                <span class="text-xs font-bold text-white uppercase">Supertrend Trend</span>
              </Badge>
              <Badge variant="outline" class="px-4 py-2 rounded-xl">
                <span class="block text-[10px] font-black text-gray-600 uppercase tracking-widest mb-1">Exit Engine</span>
                <span class="text-xs font-bold text-white uppercase">Dynamic ATR + SL</span>
              </Badge>
            </div>
          </div>

          <div class="grid grid-cols-1 sm:grid-cols-2 gap-4">
            <div class="bg-white/5 rounded-2xl p-6 border border-white/10">
              <h4 class="text-[10px] font-black text-gray-500 uppercase tracking-widest mb-4">Risk Parameters</h4>
              <div class="flex flex-col gap-3">
                <For each={riskParameters()}>
                  {(param) => (
                    <div class="flex items-center justify-between">
                      <span class="text-[11px] font-bold text-gray-400">{param.label}</span>
                      <span class="text-[10px] font-black text-white uppercase tracking-tighter">{param.value}</span>
                    </div>
                  )}
                </For>
              </div>
            </div>

            <div class="bg-white/5 rounded-2xl p-6 border border-white/10">
              <h4 class="text-[10px] font-black text-gray-500 uppercase tracking-widest mb-4">Signal Filters</h4>
              <div class="flex flex-col gap-3">
                <For each={signalFilters()}>
                  {(filter) => (
                    <div class="flex items-center justify-between">
                      <span class="text-[11px] font-bold text-gray-400">{filter.label}</span>
                      <span class="text-[10px] font-black text-white uppercase tracking-tighter">{filter.value}</span>
                    </div>
                  )}
                </For>
              </div>
            </div>
          </div>
        </div>
      </div>
    </div>
  )
}
