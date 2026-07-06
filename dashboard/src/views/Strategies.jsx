import { createSignal, onMount, For, createMemo, Show } from 'solid-js'
import { useNavigate } from '@solidjs/router'
import { useStrategies } from '../stores/useStrategies'

export default function Strategies() {
  const navigate = useNavigate()
  const { strategies, loading, error, fetchAll } = useStrategies()
  const [activeTab, setActiveTab] = createSignal('All')

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

  const getStatusClass = (status) => {
    switch (status) {
      case 'active': return 'bg-emerald-500/10 text-emerald-400 border border-emerald-500/20'
      case 'draft': return 'bg-amber-500/10 text-amber-400 border border-amber-500/20'
      case 'archived': return 'bg-gray-500/10 text-gray-400 border border-gray-500/20'
      default: return 'bg-white/5 text-white/50 border border-white/5'
    }
  }

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

      {/* Filter Tabs */}
      <div class="flex items-center justify-between border-b border-white/5 pb-2.5 gap-4">
        <div class="flex items-center gap-2">
          {['All', 'Active', 'Draft', 'Archived'].map(tab => (
            <button
              onClick={() => setActiveTab(tab)}
              class={`px-4 py-1.5 rounded-xl text-[10px] font-black uppercase tracking-wider transition-all ${
                activeTab() === tab ? 'bg-primary-600/15 text-primary-400 border border-primary-500/30' : 'text-gray-400 hover:text-white border border-transparent'
              }`}
            >
              {tab}
            </button>
          ))}
        </div>
        <span class="text-[9px] font-bold text-gray-500 font-mono">
          Showing {filteredStrategies().length} strategies
        </span>
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
