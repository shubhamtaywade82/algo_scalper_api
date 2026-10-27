import { Show, onMount } from 'solid-js'
import { Portal } from 'solid-js/web'
import { useMarketBrief } from '../stores/useMarketBrief'
import MarketBriefSheet from '../components/reports/MarketBriefSheet'

export default function MarketBrief() {
  const { brief, inProgress, loading, generating, error, fetchLatest, requestRefresh } = useMarketBrief()

  onMount(() => { fetchLatest() })

  const printReport = () => window.print()

  return (
    <div class="space-y-4">
      <div class="mb-no-print flex flex-wrap items-center justify-between gap-4 bg-white/[0.01] border border-white/5 rounded-2xl p-4">
        <div>
          <h2 class="text-sm font-black uppercase tracking-[0.2em] text-white">Market Brief</h2>
          <p class="text-[10px] text-gray-500 mt-1">
            One-page deterministic snapshot with validated AI commentary. Generating a report never places or modifies orders.
          </p>
        </div>
        <div class="flex items-center gap-2">
          <Show when={generating() || inProgress()}>
            <span class="text-[10px] font-bold uppercase tracking-wider text-amber-400 animate-pulse">
              Generating… {inProgress()?.status ? `(${inProgress().status})` : ''}
            </span>
          </Show>
          <button
            type="button"
            onClick={() => requestRefresh()}
            disabled={generating()}
            class="text-[10px] font-black uppercase tracking-wider px-4 py-2 rounded-lg bg-primary-600 hover:bg-primary-500 disabled:opacity-40 disabled:cursor-not-allowed text-white"
          >
            Generate / refresh
          </button>
          <button
            type="button"
            onClick={printReport}
            disabled={!brief()}
            class="text-[10px] font-black uppercase tracking-wider px-4 py-2 rounded-lg border border-white/10 hover:bg-white/5 disabled:opacity-40 disabled:cursor-not-allowed text-gray-200"
          >
            Print / Save PDF
          </button>
        </div>
      </div>

      <Show when={error()}>
        <div class="mb-no-print text-[11px] text-rose-300 bg-rose-500/10 border border-rose-500/20 rounded-xl px-4 py-3">
          {error()}
        </div>
      </Show>

      <Show when={!loading() || brief()} fallback={<div class="text-[11px] text-gray-500 px-2">Loading latest report…</div>}>
        <Show
          when={brief()}
          fallback={
            <div class="text-[11px] text-gray-400 bg-white/[0.02] border border-white/5 rounded-xl px-4 py-6">
              NO DATA — no Market Brief has been generated for this mode yet. Use “Generate / refresh”.
            </div>
          }
        >
          <div class="mb-sheet-frame">
            <MarketBriefSheet brief={brief()} />
          </div>
          <Portal ref={(el) => { el.className = 'mb-print-portal' }}>
            <MarketBriefSheet brief={brief()} />
          </Portal>
        </Show>
      </Show>
    </div>
  )
}
