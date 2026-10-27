import { Show, onMount } from 'solid-js'
import { Portal } from 'solid-js/web'
import { useLiveMarketBrief, LIVE_POLL_MS } from '../stores/useLiveMarketBrief'
import MarketBriefSheet from '../components/reports/MarketBriefSheet'

// Market Mood: realtime Market Brief. Facts refresh every few seconds from
// GET /api/reports/market_brief/live (never calls the LLM); AI commentary is the
// latest validated analysis, refreshed every 15 min in market hours or on demand.
export default function MarketBrief() {
  const live = useLiveMarketBrief()
  onMount(() => live.start())

  const brief = () => live.brief()
  const aiBusy = () => live.requestingAi() || Boolean(brief()?.in_progress)
  const secondsSince = () => {
    const last = live.lastSuccessAt()
    return last ? Math.max(0, Math.round((live.now() - last) / 1000)) : null
  }

  return (
    <div class="space-y-4">
      <div class="mb-no-print flex flex-wrap items-center justify-between gap-4 bg-white/[0.01] border border-white/5 rounded-2xl p-4">
        <div>
          <h2 class="text-sm font-black uppercase tracking-[0.2em] text-white">Market Mood · Live Brief</h2>
          <p class="text-[10px] text-gray-500 mt-1">
            Facts refresh every {LIVE_POLL_MS / 1000}s from cached authoritative sources. AI commentary is validated against those facts and cannot change the setup decision. Nothing on this page places or modifies orders.
          </p>
        </div>
        <div class="flex flex-wrap items-center gap-2">
          <span class={`text-[10px] font-bold uppercase tracking-wider ${live.interrupted() ? 'text-rose-400' : 'text-emerald-400'}`} data-testid="poll-status">
            {live.lastSuccessAt() === null
              ? 'Connecting…'
              : live.interrupted()
                ? `Updates interrupted · last ${secondsSince()}s ago`
                : `Live · updated ${secondsSince()}s ago`}
          </span>
          <Show when={aiBusy()}>
            <span class="text-[10px] font-bold uppercase tracking-wider text-amber-400 animate-pulse">AI analysis running…</span>
          </Show>
          <button
            type="button"
            onClick={() => live.requestAiRefresh()}
            disabled={aiBusy()}
            class="text-[10px] font-black uppercase tracking-wider px-4 py-2 rounded-lg bg-primary-600 hover:bg-primary-500 disabled:opacity-40 disabled:cursor-not-allowed text-white"
          >
            Refresh AI analysis
          </button>
          <button
            type="button"
            onClick={() => window.print()}
            disabled={!brief()}
            class="text-[10px] font-black uppercase tracking-wider px-4 py-2 rounded-lg border border-white/10 hover:bg-white/5 disabled:opacity-40 disabled:cursor-not-allowed text-gray-200"
          >
            Print / Save PDF
          </button>
        </div>
      </div>

      <Show when={live.error()}>
        <div class="mb-no-print text-[11px] text-rose-300 bg-rose-500/10 border border-rose-500/20 rounded-xl px-4 py-3" data-testid="live-error">
          {brief() ? `Live refresh failed (${live.error()}) — showing the last successful data and retrying.` : `Could not load the Market Brief: ${live.error()}`}
        </div>
      </Show>

      <Show
        when={brief()}
        fallback={
          <Show when={!live.error()}>
            <div class="text-[11px] text-gray-500 px-2">Loading live market brief…</div>
          </Show>
        }
      >
        <MarketBriefSheet brief={brief()} variant="screen" interrupted={live.interrupted()} />
        <Portal ref={(el) => { el.className = 'mb-print-portal' }}>
          <MarketBriefSheet brief={brief()} interrupted={live.interrupted()} />
        </Portal>
      </Show>
    </div>
  )
}
