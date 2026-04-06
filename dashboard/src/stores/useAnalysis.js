import { createSignal, onMount, onCleanup } from 'solid-js'
import cable from '../cable'

const INDICES = ['NIFTY', 'SENSEX', 'BANKNIFTY']
const POLL_INTERVAL_MS = 10000

export function useAnalysis() {
  // Per-index state maps: { NIFTY: signal, SENSEX: signal, BANKNIFTY: signal }
  const liveData = Object.fromEntries(INDICES.map(k => [k, createSignal(null)]))
  const loading   = Object.fromEntries(INDICES.map(k => [k, createSignal(false)]))
  const errors    = Object.fromEntries(INDICES.map(k => [k, createSignal(null)]))

  // Historical / snapshot follow the selected Analysis tab (auto-loaded once per index per visit)
  const [activeIndex, setActiveIndex] = createSignal(null)
  const [historicalData, setHistoricalData] = createSignal(null)
  const [historicalLoading, setHistoricalLoading] = createSignal(false)
  const [snapshotLoading, setSnapshotLoading] = createSignal(false)
  const [snapshotData, setSnapshotData]   = createSignal(null)
  const [snapshotError, setSnapshotError] = createSignal(null)
  const [autoHistoricalLoadedForIndex, setAutoHistoricalLoadedForIndex] = createSignal({})
  const [autoSnapshotLoadedForIndex, setAutoSnapshotLoadedForIndex] = createSignal({})

  let pollTimer = null
  let subscription = null

  function applyWsUpdate(data) {
    if (!data) return
    
    // Check if packet contains index-specific analysis data
    INDICES.forEach(idx => {
      const key = idx.toLowerCase()
      const analysisData = data[idx] || data[key] || (data.indices && (data.indices[idx] || data.indices[key]))
      
      if (analysisData && typeof analysisData === 'object' && analysisData.ltp) {
        console.debug(`⚡ [Analysis:WS] Update for ${idx}:`, analysisData)
        const [, setData] = liveData[idx]
        setData(prev => ({ ...prev, ...analysisData }))
      }
    })
  }

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

  /** @param {string[] | undefined} keys when set, only those in INDICES are polled */
  function fetchAll(keys) {
    const list =
      Array.isArray(keys) && keys.length > 0
        ? keys.filter((k) => INDICES.includes(k))
        : INDICES
    list.forEach((idx) => fetchOne(idx))
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

  function ensureAutoLoadedDetails(index, { skipAiSnapshot = false } = {}) {
    if (!index || !INDICES.includes(index)) return

    const histDone = autoHistoricalLoadedForIndex()
    if (!histDone[index]) {
      setAutoHistoricalLoadedForIndex({ ...histDone, [index]: true })
      void fetchHistorical(index)
    }

    if (skipAiSnapshot) return

    const snapDone = autoSnapshotLoadedForIndex()
    if (!snapDone[index]) {
      setAutoSnapshotLoadedForIndex({ ...snapDone, [index]: true })
      void fetchAiSnapshot(index)
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
        const msg = data.message || data.error || `HTTP ${res.status}`
        throw new Error(msg)
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

    subscription = cable.subscriptions.create('DashboardChannel', {
      connected() { console.log('✅ [Analysis:WS] Connected') },
      received(data) { applyWsUpdate(data) }
    })
  })

  onCleanup(() => {
    clearInterval(pollTimer)
    subscription?.unsubscribe()
  })

  return {
    INDICES,
    liveData:        (idx) => liveData[idx][0](),
    isLoading:       (idx) => loading[idx][0](),
    getError:        (idx) => errors[idx][0](),
    fetchOne,
    fetchAll,
    fetchHistorical,
    fetchAiSnapshot,
    ensureAutoLoadedDetails,
    activeIndex,
    historicalData,
    historicalLoading,
    snapshotLoading,
    snapshotData,
    snapshotError,
  }
}
