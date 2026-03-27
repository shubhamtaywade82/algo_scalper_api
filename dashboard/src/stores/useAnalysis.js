import { createSignal, onMount, onCleanup } from 'solid-js'

const INDICES = ['NIFTY', 'SENSEX', 'BANKNIFTY']
const POLL_INTERVAL_MS = 30000

export function useAnalysis() {
  // Per-index state maps: { NIFTY: signal, SENSEX: signal, BANKNIFTY: signal }
  const liveData = Object.fromEntries(INDICES.map(k => [k, createSignal(null)]))
  const loading   = Object.fromEntries(INDICES.map(k => [k, createSignal(false)]))
  const errors    = Object.fromEntries(INDICES.map(k => [k, createSignal(null)]))

  // Historical / snapshot are still per-selected-index (on-demand, not auto-polled)
  const [activeIndex, setActiveIndex] = createSignal(null) // which index has expanded historical/snapshot
  const [historicalData, setHistoricalData] = createSignal(null)
  const [historicalLoading, setHistoricalLoading] = createSignal(false)
  const [snapshotLoading, setSnapshotLoading] = createSignal(false)
  const [snapshotData, setSnapshotData]   = createSignal(null)
  const [snapshotError, setSnapshotError] = createSignal(null)

  let pollTimer = null

  async function fetchOne(index) {
    const [, setData] = liveData[index]
    const [, setLoad] = loading[index]
    const [, setErr]  = errors[index]
    try {
      setLoad(true)
      setErr(null)
      const res = await fetch(`/api/analysis/${index}`)
      if (!res.ok) throw new Error(`HTTP ${res.status}`)
      setData(await res.json())
    } catch (e) {
      console.error(`[Analysis] fetch failed for ${index}:`, e)
      setErr(e.message)
    } finally {
      setLoad(false)
    }
  }

  function fetchAll() {
    INDICES.forEach(idx => fetchOne(idx))
  }

  async function fetchHistorical(index, weeks = 8) {
    setActiveIndex(index)
    try {
      setHistoricalLoading(true)
      const res = await fetch(`/api/analysis/${index}/historical?weeks=${weeks}`)
      if (!res.ok) throw new Error(`HTTP ${res.status}`)
      setHistoricalData(await res.json())
    } catch (e) {
      console.error('[Analysis] historical fetch failed:', e)
      setHistoricalData({ error: e.message })
    } finally {
      setHistoricalLoading(false)
    }
  }

  async function fetchAiSnapshot(index) {
    setActiveIndex(index)
    setSnapshotLoading(true)
    setSnapshotError(null)
    setSnapshotData(null)
    try {
      const res = await fetch(`/api/analysis/${index}/ai_snapshot`, { method: 'POST' })
      if (!res.ok) {
        const data = await res.json().catch(() => ({}))
        throw new Error(data.error || `HTTP ${res.status}`)
      }
      const data = await res.json()
      setSnapshotData(data.snapshot)
    } catch (e) {
      setSnapshotError(e.message || 'Snapshot failed')
    } finally {
      setSnapshotLoading(false)
    }
  }

  onMount(() => {
    fetchAll()
    pollTimer = setInterval(fetchAll, POLL_INTERVAL_MS)
  })

  onCleanup(() => clearInterval(pollTimer))

  return {
    INDICES,
    liveData:        (idx) => liveData[idx][0](),
    isLoading:       (idx) => loading[idx][0](),
    getError:        (idx) => errors[idx][0](),
    fetchOne,
    fetchAll,
    fetchHistorical,
    fetchAiSnapshot,
    activeIndex,
    historicalData,
    historicalLoading,
    snapshotLoading,
    snapshotData,
    snapshotError,
  }
}
