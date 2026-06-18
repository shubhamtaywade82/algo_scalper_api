import { createEffect, createMemo, createSignal } from 'solid-js'
import { For, Show } from 'solid-js'
import { useDashboardContext } from '../context/DashboardContext'
import { useAnalysis } from '../stores/useAnalysis'
import MarketOverview from '../components/analysis/MarketOverview'
import SmcAnalysis from '../components/analysis/SmcAnalysis'
import AiInsights from '../components/analysis/AiInsights'
import HistoricalBehavior from '../components/analysis/HistoricalBehavior'
import ExpectedValueRiskPanel from '../components/analysis/ExpectedValueRiskPanel'
import CalibrationPanel from '../components/analysis/CalibrationPanel'

const INDEX_LTP_KEY = { NIFTY: 'nifty', SENSEX: 'sensex', BANKNIFTY: 'banknifty' }
const DEFAULT_TAB_ORDER = ['NIFTY', 'BANKNIFTY', 'SENSEX']

function watchlistTabKeys(subscribedRows) {
  const keys = new Set(
    (subscribedRows || []).map((r) => (r.key || '').toString().toUpperCase()).filter(Boolean)
  )
  const hit = DEFAULT_TAB_ORDER.filter((k) => keys.has(k))
  return hit.length > 0 ? hit : [...DEFAULT_TAB_ORDER]
}

export default function Analysis() {
  const dashCtx = useDashboardContext()
  const {
    liveData, isLoading, getError,
    fetchOne, fetchAll, fetchHistorical, fetchRiskExplorer, fetchAiSnapshot, ensureAutoLoadedDetails,
    activeIndex, historicalData, historicalLoading, riskExplorerData, riskExplorerLoading,
    snapshotLoading, snapshotData, snapshotError,
  } = useAnalysis()

  const tabKeys = createMemo(() => watchlistTabKeys(dashCtx.subscribedIndices?.()))
  const [selectedTab, setSelectedTab] = createSignal(DEFAULT_TAB_ORDER[0])

  createEffect(() => {
    const tabs = tabKeys()
    const first = tabs[0] || DEFAULT_TAB_ORDER[0]
    const cur = selectedTab()
    if (!tabs.includes(cur)) setSelectedTab(first)
  })

  createEffect(() => {
    const idx = selectedTab()
    if (!idx || isLoading(idx) || !liveData(idx)) return
    const gated = liveData(idx).session?.generative_ai_gated === true
    ensureAutoLoadedDetails(idx, { skipAiSnapshot: gated })
  })

  const tabLoading = createMemo(() => tabKeys().some((idx) => isLoading(idx)))

  const panelData = createMemo(() => {
    const idx = selectedTab()
    const d = liveData(idx)
    if (!d) return null
    const rtLtp = dashCtx.indices?.()?.[INDEX_LTP_KEY[idx]]
    return { ...d, ltp: rtLtp || d.ltp }
  })

  const detailActiveForPanel = createMemo(
    () => activeIndex() === selectedTab()
  )

  return (
    <div class="space-y-6">
      <div class="flex items-center justify-between flex-wrap gap-4">
        <h2 class="text-xs font-black uppercase tracking-widest text-gray-400">Market Analysis</h2>
        <button
          onClick={() => fetchAll(tabKeys())}
          disabled={tabLoading()}
          class="px-4 py-2 rounded-lg text-[10px] font-black uppercase tracking-widest glass border border-white/10 text-gray-400 hover:text-white hover:border-primary-500/30 transition-all duration-300 disabled:opacity-40"
        >
          {tabLoading() ? '↻ Loading...' : '↻ Refresh All'}
        </button>
      </div>

      <div class="flex flex-wrap gap-1 p-1 rounded-xl glass border border-white/10 bg-white/[0.02]">
        <For each={tabKeys()}>
          {(idx) => (
            <button
              type="button"
              onClick={() => setSelectedTab(idx)}
              class={`relative px-4 py-2.5 rounded-lg text-[10px] font-black uppercase tracking-widest transition-all duration-300 flex items-center gap-2
                ${selectedTab() === idx
                  ? 'bg-primary-500/20 text-primary-300 border border-primary-500/40 shadow-[0_0_20px_rgba(59,130,246,0.12)]'
                  : 'text-gray-500 border border-transparent hover:text-gray-300 hover:bg-white/5'}`}
            >
              {idx}
              <Show when={isLoading(idx)}>
                <span class="w-2.5 h-2.5 border border-primary-400/40 border-t-primary-400 rounded-full animate-spin" />
              </Show>
            </button>
          )}
        </For>
      </div>

      <div class="space-y-4">
        <div class="flex items-center justify-between flex-wrap gap-2">
          <h3 class="text-sm font-black uppercase tracking-[0.2em] text-primary-400">{selectedTab()}</h3>
          <div class="flex items-center gap-3">
            <Show when={getError(selectedTab()) && !isLoading(selectedTab())}>
              <button
                type="button"
                onClick={() => fetchOne(selectedTab())}
                class="text-[9px] font-bold text-rose-400 hover:text-rose-300 tracking-widest uppercase"
              >
                ↻ Retry
              </button>
            </Show>
          </div>
        </div>

        <Show when={isLoading(selectedTab()) && !liveData(selectedTab())}>
          <div class="flex flex-col items-center justify-center py-12 gap-3">
            <div class="w-6 h-6 border-2 border-white/10 border-t-primary-500 rounded-full animate-spin" />
            <span class="text-[9px] font-black text-gray-500 tracking-widest uppercase">
              Analysing {selectedTab()}
            </span>
          </div>
        </Show>

        <Show when={getError(selectedTab()) && !liveData(selectedTab())}>
          <div class="glass rounded-2xl p-6 text-center border border-rose-500/20">
            <div class="text-rose-400 text-sm font-bold">{getError(selectedTab())}</div>
          </div>
        </Show>

        <Show when={panelData()}>
          <Show when={panelData().background_refresh}>
            <div class="flex items-center gap-2 px-4 py-2 rounded-lg bg-primary-500/5 border border-primary-500/10">
              <div class="w-2 h-2 rounded-full bg-primary-400 animate-pulse" />
              <span class="text-[9px] font-bold text-primary-400 tracking-wider uppercase">
                Computing {panelData().background_refresh.refreshing.join(', ')} in background...
              </span>
            </div>
          </Show>
          <MarketOverview data={panelData()} />
          <SmcAnalysis smc={panelData().smc} />
          <AiInsights
            analysis={panelData().ai_analysis}
            snapshotData={detailActiveForPanel() ? snapshotData() : null}
            snapshotLoading={detailActiveForPanel() ? snapshotLoading() : false}
            snapshotError={detailActiveForPanel() ? snapshotError() : null}
            onSnapshot={() => fetchAiSnapshot(selectedTab())}
          />
          <HistoricalBehavior
            data={detailActiveForPanel() ? historicalData() : null}
            loading={detailActiveForPanel() ? historicalLoading() : false}
            onLoad={() => fetchHistorical(selectedTab())}
          />
          <ExpectedValueRiskPanel
            data={detailActiveForPanel() ? riskExplorerData() : null}
            loading={detailActiveForPanel() ? riskExplorerLoading() : false}
            onLoad={() => fetchRiskExplorer(selectedTab())}
          />
          <Show when={detailActiveForPanel() && historicalData()}>
            <CalibrationPanel data={historicalData()} />
          </Show>
        </Show>
      </div>
    </div>
  )
}
