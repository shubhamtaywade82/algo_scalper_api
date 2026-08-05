import { createMemo, createSignal, onMount } from 'solid-js'
import { For, Show } from 'solid-js'
import { useNavigate } from '@solidjs/router'
import { useDashboardContext } from '../context/DashboardContext'
import { useStrategies } from '../stores/useStrategies'
import { expiryBadgeMeta } from '../lib/expiryBadge'

function getStatusClass(status) {
  if (status === 'running') return 'bg-emerald-500/10 text-emerald-400'
  if (status === 'stopped') return 'bg-gray-500/10 text-gray-400'
  if (status === 'errored') return 'bg-rose-500/10 text-rose-400'
  return 'bg-white/5 text-gray-500'
}

export default function Strategies() {
  const navigate = useNavigate()
  const { subscribedIndices, config } = useDashboardContext()
  const { strategies, fetchAll, loading } = useStrategies()
  const [activeTab] = createSignal('All')

  onMount(() => {
    fetchAll()
  })

  // Filter strategies based on tab selection
  const filteredStrategies = createMemo(() => {
    const list = strategies() || []
    if (activeTab() === 'All') {
      return list.filter(s => s.status !== 'archived')
    }
    return list.filter(s => s.status === activeTab().toLowerCase())
  })

  const indicesList = createMemo(() => subscribedIndices() || [])

  return (
    <div class="space-y-6">
      {/* Header Bar */}
      <div class="flex items-center justify-between">
        <div>
          <p class="text-[10px] font-bold text-gray-500 uppercase tracking-wider">Algorithmic Engine</p>
        </div>
        <button
          onClick={() => navigate('/strategies/creator')}
          class="px-5 py-2.5 bg-primary-600 hover:bg-primary-500 rounded-xl text-xs font-black uppercase tracking-wider text-white shadow-lg transition-all"
        >
          + Create Strategy
        </button>
      </div>

      <div class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-6">
        <For each={indicesList()}>
          {(idx) => (
            <div class="glass glass-hover p-6 rounded-2xl flex flex-col gap-4 group overflow-hidden relative min-h-[160px]">
              <div class="absolute top-0 right-0 w-32 h-32 bg-primary-500/5 blur-3xl group-hover:bg-primary-500/10 transition-colors"></div>
              <div class="flex items-center justify-between relative z-10 gap-2">
                <div class="flex flex-col min-w-0">
                  <span class="text-xl font-black text-white tracking-tight">{idx.key}</span>
                  <span class="text-xs font-bold text-gray-500 uppercase tracking-widest mt-0.5">{idx.timeframe} Interval</span>
                  {(() => {
                    const b = expiryBadgeMeta(idx)
                    return (
                      <div class="flex flex-wrap items-center gap-1.5 mt-2">
                        <span class={`text-[9px] font-black uppercase tracking-tight px-2 py-0.5 rounded border ${b.className}`}>
                          {b.text}
                        </span>
                        <Show when={b.sub}>
                          <span class="text-[9px] font-bold text-gray-600">{b.sub}</span>
                        </Show>
                      </div>
                    )
                  })()}
                </div>
                <div class="px-3 py-1 rounded-full bg-primary-500/10 border border-primary-500/20 shrink-0">
                  <span class="text-xs font-black text-primary-400 uppercase tracking-tighter">{idx.strategy}</span>
                </div>
              </div>
              <div class="flex flex-col gap-2 mt-auto relative z-10">
                <div class="flex items-center justify-between text-[10px] font-bold uppercase tracking-widest text-gray-600">
                  <span>Status</span>
                  <span class="text-emerald-500">Scoping Index</span>
                </div>
                <div class="w-full bg-white/5 h-1 rounded-full overflow-hidden">
                  <div class="bg-primary-500 h-full w-2/3 animate-pulse"></div>
                </div>
              </div>
            </div>
          )}
        </For>
      </div>

      {/* Strategies Grid */}
      <Show when={!loading()} fallback={
        <div class="text-center py-20 text-xs font-black text-gray-500 uppercase tracking-widest animate-pulse">
          Loading strategies...
        </div>
      }>
        <div class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-6">
          <For each={filteredStrategies()}>
            {(s) => (
              <div
                onClick={() => navigate(`/strategies/${s.id}`)}
                class="glass glass-hover p-5 rounded-2xl cursor-pointer border border-white/5 flex flex-col justify-between h-[190px] group transition-all"
              >
                <div>
                  {/* Top line: Name + status */}
                  <div class="flex items-start justify-between gap-3">
                    <h3 class="text-xs font-black text-white group-hover:text-primary-400 transition-colors uppercase tracking-wide">
                      {s.name}
                    </h3>
                    <span class={`text-[8px] font-black uppercase px-2 py-0.5 rounded-md ${getStatusClass(s.status)}`}>
                      {s.status}
                    </span>
                  </div>

                  {/* Version & tags */}
                  <div class="flex flex-wrap items-center gap-1.5 mt-2">
                    <span class="text-[8px] font-bold bg-white/5 text-gray-400 px-1.5 py-0.5 rounded">
                      v{s.version}
                    </span>
                    <For each={s.instruments || []}>
                      {inst => (
                        <span class="text-[8px] font-bold bg-primary-600/10 text-primary-400 border border-primary-500/10 px-1.5 py-0.5 rounded">
                          {inst}
                        </span>
                      )}
                    </For>
                  </div>

                  {/* Description */}
                  <p class="text-[10px] text-gray-500 mt-3 line-clamp-2 leading-relaxed">
                    {s.description || 'No description provided.'}
                  </p>
                </div>

                {/* Bottom line: Backtest results or author info */}
                <div class="border-t border-white/5 pt-3 flex items-center justify-between text-[9px]">
                  <div class="flex items-center gap-1 text-gray-500">
                    <span class="font-bold">Runtime:</span>
                    <span class="font-black text-gray-300 font-mono">{s.runtime} · {s.timeframe}</span>
                  </div>

                  {s.backtest_results?.win_rate ? (
                    <div class="flex items-center gap-2">
                      <span class="text-gray-500 font-bold">Win Rate:</span>
                      <span class="text-emerald-400 font-black font-mono">{s.backtest_results.win_rate}%</span>
                    </div>
                  ) : (
                    <span class="text-gray-600 font-bold uppercase tracking-wider text-[8px]">No backtest run</span>
                  )}
                </div>
              </div>
            )}
          </For>

          {filteredStrategies().length === 0 && (
            <div class="col-span-full py-16 text-center">
              <span class="text-3xl block mb-3">🛠️</span>
              <h4 class="text-xs font-black text-white uppercase tracking-wider">No strategies found</h4>
              <p class="text-[10px] text-gray-500 mt-1">Get started by creating your first trading strategy.</p>
            </div>
          )}
        </div>
      </Show>
    </div>
  )
}
