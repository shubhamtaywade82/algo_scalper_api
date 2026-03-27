import { createMemo } from 'solid-js'
import { For, Show } from 'solid-js'
import { useDashboardContext } from '../context/DashboardContext'
import { useAnalysis } from '../stores/useAnalysis'
import MarketOverview from '../components/analysis/MarketOverview'
import SmcAnalysis from '../components/analysis/SmcAnalysis'
import AiInsights from '../components/analysis/AiInsights'
import HistoricalBehavior from '../components/analysis/HistoricalBehavior'
import CalibrationPanel from '../components/analysis/CalibrationPanel'

const INDEX_LTP_KEY = { NIFTY: 'nifty', SENSEX: 'sensex', BANKNIFTY: 'banknifty' }

export default function Analysis() {
  const dashCtx = useDashboardContext()
  const {
    INDICES, liveData, isLoading, getError,
    fetchOne, fetchAll, fetchHistorical, fetchAiSnapshot,
    activeIndex, historicalData, historicalLoading,
    snapshotLoading, snapshotData, snapshotError,
  } = useAnalysis()

  const anyLoading = createMemo(() => INDICES.some(idx => isLoading(idx)))

  return (
    <div class="space-y-6">
      <div class="flex items-center justify-between flex-wrap gap-4">
        <h2 class="text-xs font-black uppercase tracking-widest text-gray-400">Market Analysis</h2>
        <button
          onClick={() => fetchAll()}
          disabled={anyLoading()}
          class="px-4 py-2 rounded-lg text-[10px] font-black uppercase tracking-widest glass border border-white/10 text-gray-400 hover:text-white hover:border-primary-500/30 transition-all duration-300 disabled:opacity-40"
        >
          {anyLoading() ? '↻ Loading...' : '↻ Refresh All'}
        </button>
      </div>

      <div class="space-y-8">
        <For each={INDICES}>
          {(idx, i) => {
            const data = createMemo(() => {
              const d = liveData(idx)
              if (!d) return null
              const rtLtp = dashCtx.indices?.()?.[INDEX_LTP_KEY[idx]]
              return { ...d, ltp: rtLtp || d.ltp }
            })
            const isActive = createMemo(() => activeIndex() === idx)

            return (
              <div class="space-y-4">
                <div class="flex items-center justify-between">
                  <h3 class="text-sm font-black uppercase tracking-[0.2em] text-primary-400">{idx}</h3>
                  <Show when={isLoading(idx)}>
                    <div class="flex items-center gap-2 text-[9px] font-bold text-gray-500 tracking-widest uppercase">
                      <div class="w-3 h-3 border border-white/10 border-t-primary-500 rounded-full animate-spin" />
                      Analysing...
                    </div>
                  </Show>
                  <Show when={getError(idx) && !isLoading(idx)}>
                    <button
                      onClick={() => fetchOne(idx)}
                      class="text-[9px] font-bold text-rose-400 hover:text-rose-300 tracking-widest uppercase"
                    >
                      ↻ Retry
                    </button>
                  </Show>
                </div>

                <Show when={isLoading(idx) && !liveData(idx)}>
                  <div class="flex flex-col items-center justify-center py-12 gap-3">
                    <div class="w-6 h-6 border-2 border-white/10 border-t-primary-500 rounded-full animate-spin" />
                    <span class="text-[9px] font-black text-gray-500 tracking-widest uppercase">Analysing {idx}</span>
                  </div>
                </Show>

                <Show when={getError(idx) && !liveData(idx)}>
                  <div class="glass rounded-2xl p-6 text-center border border-rose-500/20">
                    <div class="text-rose-400 text-sm font-bold">{getError(idx)}</div>
                  </div>
                </Show>

                <Show when={data()}>
                  <Show when={data().background_refresh}>
                    <div class="flex items-center gap-2 px-4 py-2 rounded-lg bg-primary-500/5 border border-primary-500/10">
                      <div class="w-2 h-2 rounded-full bg-primary-400 animate-pulse" />
                      <span class="text-[9px] font-bold text-primary-400 tracking-wider uppercase">
                        Computing {data().background_refresh.refreshing.join(', ')} in background...
                      </span>
                    </div>
                  </Show>
                  <MarketOverview data={data()} />
                  <SmcAnalysis smc={data().smc} />
                  <AiInsights
                    analysis={data().ai_analysis}
                    snapshotData={isActive() ? snapshotData() : null}
                    snapshotLoading={isActive() ? snapshotLoading() : false}
                    snapshotError={isActive() ? snapshotError() : null}
                    onSnapshot={() => fetchAiSnapshot(idx)}
                  />
                  <HistoricalBehavior
                    data={isActive() ? historicalData() : null}
                    loading={isActive() ? historicalLoading() : false}
                    onLoad={() => fetchHistorical(idx)}
                  />
                  <Show when={isActive() && historicalData()}>
                    <CalibrationPanel data={historicalData()} />
                  </Show>
                </Show>

                <Show when={i() < INDICES.length - 1}>
                  <div class="border-t border-white/5 pt-2" />
                </Show>
              </div>
            )
          }}
        </For>
      </div>
    </div>
  )
}
