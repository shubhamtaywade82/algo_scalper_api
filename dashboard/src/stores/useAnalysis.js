import { createSignal, onMount, onCleanup } from 'solid-js'

const POLL_INTERVAL_MS = 30000

export function useAnalysis() {
  // Per-index state maps: { NIFTY: signal, SENSEX: signal, BANKNIFTY: signal }
  const liveData = Object.fromEntries(INDICES.map(k => [k, createSignal(null)]))
  const loadingMap   = Object.fromEntries(INDICES.map(k => [k, createSignal(false)]))
  const errors    = Object.fromEntries(INDICES.map(k => [k, createSignal(null)]))

  // Historical / snapshot follow the selected Analysis tab (auto-loaded once per index per visit)
  const [activeIndex, setActiveIndex] = createSignal(null)
  const [historicalData, setHistoricalData] = createSignal(null)
  const [historicalLoading, setHistoricalLoading] = createSignal(false)
  const [error, setError] = createSignal(null)
  const [snapshotLoading, setSnapshotLoading] = createSignal(false)
  const [snapshotData, setSnapshotData] = createSignal(null)
  const [snapshotError, setSnapshotError] = createSignal(null)
  const [autoHistoricalLoadedForIndex, setAutoHistoricalLoadedForIndex] = createSignal({})
  const [autoSnapshotLoadedForIndex, setAutoSnapshotLoadedForIndex] = createSignal({})

  let pollTimer = null

  async function fetchLive(index) {
    const key = index || currentIndex()
    try {
      setLoading(true)
      setError(null)
      const res = await fetch(`/api/analysis/${key}`)
      if (!res.ok) throw new Error(`HTTP ${res.status}`)
      setLiveData(await res.json())
    } catch (e) {
      console.error(`[Analysis] live fetch failed for ${key}:`, e)
      setError(e.message)
    } finally {
      setLoading(false)
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
      const res = await fetch(`/api/analysis/${currentIndex()}/historical?weeks=${weeks}`)
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
    try {
      const res = await fetch(`/api/analysis/${currentIndex()}/ai_snapshot`, { method: 'POST' })
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

  function switchIndex(key) {
    setCurrentIndex(key)
    setLiveData(null)
    setHistoricalData(null)
    setSnapshotData(null)
    setSnapshotError(null)
    fetchLive(key)
  }

  onMount(() => {
    fetchLive()
    pollTimer = setInterval(() => fetchLive(), POLL_INTERVAL_MS)
  })

  onCleanup(() => {
    clearInterval(pollTimer)
  })

  return {
    INDICES,
    liveData:        (idx) => liveData[idx][0](),
    isLoading:       (idx) => loadingMap[idx][0](),
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
