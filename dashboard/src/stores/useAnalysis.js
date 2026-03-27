import { createSignal, onMount, onCleanup } from 'solid-js'

const POLL_INTERVAL_MS = 30000

export function useAnalysis() {
  const [currentIndex, setCurrentIndex] = createSignal('NIFTY')
  const [liveData, setLiveData] = createSignal(null)
  const [historicalData, setHistoricalData] = createSignal(null)
  const [loading, setLoading] = createSignal(false)
  const [historicalLoading, setHistoricalLoading] = createSignal(false)
  const [error, setError] = createSignal(null)
  const [snapshotLoading, setSnapshotLoading] = createSignal(false)
  const [snapshotData, setSnapshotData] = createSignal(null)
  const [snapshotError, setSnapshotError] = createSignal(null)

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

  async function fetchHistorical(weeks = 8) {
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

  async function fetchAiSnapshot() {
    setSnapshotLoading(true)
    setSnapshotError(null)
    try {
      const res = await fetch(`/api/analysis/${currentIndex()}/ai_snapshot`, { method: 'POST' })
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
    currentIndex, liveData, historicalData, loading, historicalLoading, error,
    fetchLive, fetchHistorical, switchIndex,
    snapshotLoading, snapshotData, snapshotError, fetchAiSnapshot
  }
}
