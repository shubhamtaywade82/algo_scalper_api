import { createSignal, createMemo, For, Show, onMount } from 'solid-js'
import { useNavigate } from '@solidjs/router'
import { useStrategies } from '../stores/useStrategies'

const demoStrategies = [
  { id: 1, name: 'ORB Breakout', version: '1.4', status: 'active', instruments: ['NIFTY', 'BANKNIFTY'], author: 'System', updated_at: '2026-07-05T14:30:00Z', timeframe: '5m', direction: 'Both', backtest: { win_rate: 62.5, profit_factor: 1.84 } },
  { id: 2, name: 'VWAP Reversal', version: '2.1', status: 'active', instruments: ['NIFTY'], author: 'System', updated_at: '2026-07-04T09:15:00Z', timeframe: '3m', direction: 'Long', backtest: { win_rate: 58.3, profit_factor: 1.52 } },
  { id: 3, name: 'Momentum Scalper', version: '0.8', status: 'draft', instruments: ['BANKNIFTY', 'FINNIFTY'], author: 'User', updated_at: '2026-07-03T16:45:00Z', timeframe: '1m', direction: 'Both', backtest: null },
  { id: 4, name: 'Mean Reversion V2', version: '1.0', status: 'draft', instruments: ['NIFTY'], author: 'User', updated_at: '2026-07-02T11:00:00Z', timeframe: '15m', direction: 'Short', backtest: { win_rate: 45.2, profit_factor: 0.98 } },
  { id: 5, name: 'Gap Fill Strategy', version: '3.2', status: 'archived', instruments: ['NIFTY', 'BANKNIFTY', 'FINNIFTY'], author: 'System', updated_at: '2026-06-28T08:30:00Z', timeframe: '5m', direction: 'Both', backtest: { win_rate: 55.1, profit_factor: 1.31 } },
  { id: 6, name: 'Trend Following Alpha', version: '1.1', status: 'active', instruments: ['BANKNIFTY'], author: 'User', updated_at: '2026-07-06T07:00:00Z', timeframe: '1h', direction: 'Long', backtest: { win_rate: 71.4, profit_factor: 2.15 } },
]

export default function Strategies() {
  const navigate = useNavigate()
  const { strategies, loading, fetchAll } = useStrategies()
  const [activeFilter, setActiveFilter] = createSignal('All')

  const filterTabs = ['All', 'Active', 'Draft', 'Archived']

  onMount(() => {
    fetchAll()
  })

  const displayStrategies = createMemo(() => {
    const s = strategies()
    return s.length > 0 ? s : demoStrategies
  })

  const filteredStrategies = createMemo(() => {
    const f = activeFilter().toLowerCase()
    const all = displayStrategies()
    if (f === 'all') return all
    return all.filter(s => s.status === f)
  })

  function statusBadgeClass(status) {
    switch (status) {
      case 'active': return 'bg-emerald-500/15 text-emerald-500 border-emerald-500/20'
      case 'draft': return 'bg-amber-500/15 text-amber-500 border-amber-500/20'
      case 'archived': return 'bg-gray-500/15 text-gray-500 border-gray-500/20'
      default: return 'bg-white/10 text-gray-400 border-white/10'
    }
  }

  function formatDate(dateStr) {
    if (!dateStr) return '—'
    const d = new Date(dateStr)
    return d.toLocaleDateString('en-IN', { day: '2-digit', month: 'short', year: 'numeric' })
  }

  return (
    <div class="space-y-6">
      {/* Header */}
      <div class="flex items-center justify-between">
        <div class="flex items-center gap-3">
          <h2 class="text-sm font-black text-white uppercase tracking-widest flex items-center gap-2">
            <span class="w-2 h-2 rounded-full bg-primary-500" />
            My Strategies
          </h2>
          <Show when={loading()}>
            <div class="w-4 h-4 border-2 border-primary-500/30 border-t-primary-500 rounded-full animate-spin" />
          </Show>
        </div>
        <button
          onClick={() => navigate('/strategies/creator')}
          class="bg-gradient-to-r from-primary-500 to-primary-600 text-white px-5 py-2.5 rounded-xl text-xs font-bold hover:opacity-90 transition flex items-center gap-2 shadow-lg shadow-primary-500/20"
        >
          <svg class="w-3.5 h-3.5" viewBox="0 0 20 20" fill="currentColor">
            <path fill-rule="evenodd" d="M10 3a1 1 0 011 1v5h5a1 1 0 110 2h-5v5a1 1 0 11-2 0v-5H4a1 1 0 110-2h5V4a1 1 0 011-1z" clip-rule="evenodd" />
          </svg>
          Create Strategy
        </button>
      </div>

      {/* Filter Tabs */}
      <div class="flex items-center gap-1.5 bg-white/5 rounded-xl p-1 w-fit">
        <For each={filterTabs}>
          {(tab) => (
            <button
              onClick={() => setActiveFilter(tab)}
              class={`px-4 py-1.5 rounded-lg text-xs font-bold transition ${
                activeFilter() === tab
                  ? 'bg-primary-500/20 text-primary-400'
                  : 'text-gray-500 hover:text-gray-300 hover:bg-white/5'
              }`}
            >
              {tab}
              <Show when={tab !== 'All'}>
                <span class="ml-1.5 text-[10px] opacity-60">
                  {displayStrategies().filter(s => tab.toLowerCase() === 'all' || s.status === tab.toLowerCase()).length}
                </span>
              </Show>
            </button>
          )}
        </For>
      </div>

      {/* Strategy Cards Grid */}
      <Show
        when={filteredStrategies().length > 0}
        fallback={
          <div class="glass rounded-2xl p-16 flex flex-col items-center justify-center text-center">
            <svg class="w-16 h-16 text-gray-700 mb-4" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1">
              <path d="M9 5H7a2 2 0 00-2 2v12a2 2 0 002 2h10a2 2 0 002-2V7a2 2 0 00-2-2h-2M9 5a2 2 0 002 2h2a2 2 0 002-2M9 5a2 2 0 012-2h2a2 2 0 012 2" stroke-linecap="round" stroke-linejoin="round" />
            </svg>
            <p class="text-sm font-bold text-gray-500 mb-1">No strategies found</p>
            <p class="text-xs text-gray-700 mb-6">
              <Show when={activeFilter() !== 'All'} fallback="Create your first strategy to get started">
                No {activeFilter().toLowerCase()} strategies. Try a different filter.
              </Show>
            </p>
            <button
              onClick={() => navigate('/strategies/creator')}
              class="bg-gradient-to-r from-primary-500 to-primary-600 text-white px-5 py-2.5 rounded-xl text-xs font-bold hover:opacity-90 transition"
            >
              Create Your First Strategy
            </button>
          </div>
        }
      >
        <div class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-6">
          <For each={filteredStrategies()}>
            {(strategy) => (
              <div
                onClick={() => navigate(`/strategies/${strategy.id}`)}
                class="glass glass-hover p-6 rounded-2xl cursor-pointer flex flex-col gap-3 group overflow-hidden relative"
              >
                {/* Decorative glow */}
                <div class="absolute top-0 right-0 w-32 h-32 bg-primary-500/5 blur-3xl group-hover:bg-primary-500/10 transition-colors" />

                {/* Top: Name + Version + Status */}
                <div class="flex items-start justify-between relative z-10">
                  <div class="flex flex-col min-w-0">
                    <span class="text-lg font-black text-white tracking-tight truncate">{strategy.name}</span>
                    <div class="flex items-center gap-2 mt-1.5">
                      <span class="text-[10px] font-bold text-gray-600 bg-white/5 px-2 py-0.5 rounded-md">
                        v{strategy.version}
                      </span>
                      <span class={`text-[10px] font-black uppercase tracking-tight px-2 py-0.5 rounded-md border ${statusBadgeClass(strategy.status)}`}>
                        {strategy.status}
                      </span>
                    </div>
                  </div>
                  {/* Arrow icon */}
                  <svg class="w-4 h-4 text-gray-700 group-hover:text-primary-400 transition flex-shrink-0 mt-1" viewBox="0 0 20 20" fill="currentColor">
                    <path fill-rule="evenodd" d="M7.293 14.707a1 1 0 010-1.414L10.586 10 7.293 6.707a1 1 0 011.414-1.414l4 4a1 1 0 010 1.414l-4 4a1 1 0 01-1.414 0z" clip-rule="evenodd" />
                  </svg>
                </div>

                {/* Instruments */}
                <div class="flex flex-wrap gap-1.5 relative z-10">
                  <For each={strategy.instruments || []}>
                    {(inst) => (
                      <span class="bg-white/5 border border-white/10 text-[10px] font-bold text-gray-400 px-2.5 py-0.5 rounded-full">
                        {inst}
                      </span>
                    )}
                  </For>
                </div>

                {/* Meta info */}
                <div class="flex items-center justify-between text-[11px] text-gray-600 relative z-10">
                  <span class="font-medium">{strategy.author}</span>
                  <span class="font-medium">{formatDate(strategy.updated_at)}</span>
                </div>

                <div class="flex items-center gap-3 text-[11px] text-gray-500 relative z-10">
                  <span class="flex items-center gap-1">
                    <svg class="w-3 h-3" viewBox="0 0 20 20" fill="currentColor">
                      <path fill-rule="evenodd" d="M10 18a8 8 0 100-16 8 8 0 000 16zm1-12a1 1 0 10-2 0v4a1 1 0 00.293.707l2.828 2.829a1 1 0 101.415-1.415L11 9.586V6z" clip-rule="evenodd" />
                    </svg>
                    {strategy.timeframe}
                  </span>
                  <span class="flex items-center gap-1">
                    <svg class="w-3 h-3" viewBox="0 0 20 20" fill="currentColor">
                      <path d="M5 12a1 1 0 102 0V6.414l1.293 1.293a1 1 0 001.414-1.414l-3-3a1 1 0 00-1.414 0l-3 3a1 1 0 001.414 1.414L5 6.414V12zM15 8a1 1 0 10-2 0v5.586l-1.293-1.293a1 1 0 00-1.414 1.414l3 3a1 1 0 001.414 0l3-3a1 1 0 00-1.414-1.414L15 13.586V8z" />
                    </svg>
                    {strategy.direction}
                  </span>
                </div>

                {/* Backtest Stats */}
                <Show when={strategy.backtest}>
                  <div class="flex items-center gap-4 pt-2 mt-auto border-t border-white/5 relative z-10">
                    <div class="flex items-center gap-1.5">
                      <span class="text-[10px] text-gray-600 font-bold">Win Rate</span>
                      <span class={`text-[11px] font-black text-data ${strategy.backtest.win_rate >= 50 ? 'text-emerald-500' : 'text-amber-500'}`}>
                        {strategy.backtest.win_rate}%
                      </span>
                    </div>
                    <div class="flex items-center gap-1.5">
                      <span class="text-[10px] text-gray-600 font-bold">PF</span>
                      <span class={`text-[11px] font-black text-data ${strategy.backtest.profit_factor >= 1.5 ? 'text-emerald-500' : 'text-amber-500'}`}>
                        {strategy.backtest.profit_factor}
                      </span>
                    </div>
                  </div>
                </Show>
              </div>
            )}
          </For>
        </div>
      </Show>
    </div>
  )
}
