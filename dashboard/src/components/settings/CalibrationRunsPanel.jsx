import { createSignal, createMemo, onMount } from 'solid-js'
import { Show, For } from 'solid-js'

function buildDiff(proposedPatch, currentSnapshot) {
  const pairs = []
  function walk(obj, prefix) {
    for (const [k, v] of Object.entries(obj || {})) {
      const fullKey = prefix ? `${prefix}.${k}` : k
      if (v !== null && typeof v === 'object') {
        walk(v, fullKey)
      } else {
        const cur = currentSnapshot?.[fullKey]
        pairs.push({ key: fullKey, current: cur ?? null, proposed: v })
      }
    }
  }
  walk(proposedPatch, '')
  return pairs
}

export default function CalibrationRunsPanel(props) {
  const [runs, setRuns] = createSignal([])
  const [loading, setLoading] = createSignal(false)
  const [error, setError] = createSignal(null)
  const [applying, setApplying] = createSignal(null)
  const [applyError, setApplyError] = createSignal(null)
  const [applySuccess, setApplySuccess] = createSignal(false)

  async function fetchRuns() {
    setLoading(true)
    setError(null)
    try {
      const res = await fetch('/api/calibration_runs?limit=20')
      if (!res.ok) throw new Error(`HTTP ${res.status}`)
      const all = await res.json()
      setRuns(all.filter(r => r.symbol === props.symbol).slice(0, 5))
    } catch (e) {
      setError(e.message)
    } finally {
      setLoading(false)
    }
  }

  async function applyRun(run) {
    if (applying()) return
    if (!window.confirm(`Apply calibration patch for ${props.symbol}? This will update live config.`)) return
    setApplying(run.id)
    setApplyError(null)
    setApplySuccess(false)
    try {
      const res = await fetch(`/api/calibration_runs/${run.id}/apply`, { method: 'POST' })
      const data = await res.json()
      if (!res.ok) throw new Error(data.error || `HTTP ${res.status}`)
      setApplySuccess(true)
      setTimeout(() => setApplySuccess(false), 5000)
      await fetchRuns()
    } catch (e) {
      setApplyError(e.message)
    } finally {
      setApplying(null)
    }
  }

  onMount(fetchRuns)

  return (
    <div class="mt-8 border-t border-gray-800 pt-6">
      <div class="flex items-center justify-between mb-4">
        <h3 class="text-sm font-bold text-gray-300 uppercase tracking-widest">
          📊 Calibration Runs — {props.symbol}
        </h3>
        <button
          onClick={fetchRuns}
          disabled={loading()}
          class="text-[10px] font-bold text-gray-500 hover:text-gray-300 uppercase tracking-wider disabled:opacity-40"
        >
          {loading() ? '↻ Loading...' : '↻ Refresh'}
        </button>
      </div>

      <Show when={error()}>
        <div class="text-rose-400 text-xs mb-4">⚠ {error()}</div>
      </Show>
      <Show when={applyError()}>
        <div class="text-rose-400 text-xs mb-4">Apply failed: {applyError()}</div>
      </Show>
      <Show when={applySuccess()}>
        <div class="text-emerald-400 text-xs mb-4 font-bold">✅ Config updated — daemon picks up in ~30s</div>
      </Show>

      <Show when={loading() && !runs().length}>
        <div class="text-gray-600 text-xs py-4">Loading...</div>
      </Show>

      <Show when={!runs().length && !loading()}>
        <div class="text-gray-700 text-xs py-4">No calibration runs yet. Runs appear after the weekly job executes.</div>
      </Show>

      <Show when={runs().length > 0}>
        <div class="space-y-3">
          <For each={runs()}>
            {(run) => {
              const diffs = buildDiff(run.proposed_patch, run.current_snapshot)
              return (
                <div class={`bg-gray-900 border rounded-lg p-4 relative ${run.is_regime_shift ? 'border-amber-600/40' : 'border-gray-800'}`}>
                  <Show when={run.is_regime_shift}>
                    <div class="absolute top-2 right-2 text-[9px] font-black text-amber-400 bg-amber-400/10 px-2 py-0.5 rounded uppercase tracking-wider">
                      ⚠ Regime shift
                    </div>
                  </Show>

                  <div class="flex items-center gap-4 mb-3">
                    <span class="text-[10px] font-bold text-gray-400">
                      {new Date(run.created_at).toLocaleDateString('en-IN')}
                    </span>
                    <span class="text-[10px] text-gray-600">{run.weeks_analyzed}w · {run.strike_mode}</span>
                    <Show when={run.applied_at}>
                      <span class="text-[9px] text-emerald-400 font-bold">
                        ✓ Applied {new Date(run.applied_at).toLocaleDateString('en-IN')}
                        <Show when={run.applied_by}> via {run.applied_by}</Show>
                      </span>
                    </Show>
                  </div>

                  <div class="mb-3">
                    <Show when={diffs.length > 0} fallback={
                      <div class="text-gray-600 text-[9px] italic">No significant config changes (&lt;10% deviation from current)</div>
                    }>
                      <For each={diffs}>
                        {(diff) => (
                          <div class="flex items-center gap-2 text-[10px] font-mono py-0.5">
                            <span class="text-gray-600 flex-1 truncate">{diff.key}</span>
                            <span class="text-gray-500">{diff.current !== null ? diff.current : '—'}</span>
                            <span class="text-gray-600 mx-1">→</span>
                            <span class="text-cyan-400 font-bold">{diff.proposed}</span>
                          </div>
                        )}
                      </For>
                    </Show>
                  </div>

                  <Show when={!run.applied_at}>
                    <button
                      onClick={() => applyRun(run)}
                      disabled={applying() === run.id}
                      class={`px-4 py-1.5 text-[10px] font-black uppercase tracking-widest rounded border transition-all ${
                        applying() === run.id
                          ? 'border-gray-700 text-gray-600 cursor-not-allowed'
                          : 'border-cyan-700 text-cyan-400 hover:bg-cyan-900/20 hover:border-cyan-500'
                      }`}
                    >
                      {applying() === run.id ? 'Applying...' : 'Apply'}
                    </button>
                  </Show>
                </div>
              )
            }}
          </For>
        </div>
      </Show>
    </div>
  )
}
