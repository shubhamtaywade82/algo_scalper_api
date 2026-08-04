import { ref, onMounted, onUnmounted } from 'vue'

const POLL_INTERVAL_MS = 30000

export function useAnalysis() {
  const currentIndex = ref('NIFTY')
  const liveData = ref(null)
  const historicalData = ref(null)
  const loading = ref(false)
  const historicalLoading = ref(false)
  const error = ref(null)

  let pollTimer = null

  async function fetchLive(index) {
    const key = index || currentIndex.value
    try {
      loading.value = true
      error.value = null
      const res = await fetch(`/api/analysis/${key}`)
      if (!res.ok) throw new Error(`HTTP ${res.status}`)
      liveData.value = await res.json()
    } catch (e) {
      console.error(`[Analysis] live fetch failed for ${key}:`, e)
      error.value = e.message
    } finally {
      loading.value = false
    }
  }

  async function fetchHistorical(weeks = 8) {
    try {
      historicalLoading.value = true
      const res = await fetch(`/api/analysis/${currentIndex.value}/historical?weeks=${weeks}`)
      if (!res.ok) throw new Error(`HTTP ${res.status}`)
      historicalData.value = await res.json()
    } catch (e) {
      console.error(`[Analysis] historical fetch failed:`, e)
      historicalData.value = { error: e.message }
    } finally {
      historicalLoading.value = false
    }
  }

  // --- snapshot state ---
  const snapshotLoading = ref(false)
  const snapshotData    = ref(null)
  const snapshotError   = ref(null)

  async function fetchAiSnapshot() {
    snapshotLoading.value = true
    snapshotError.value   = null
    try {
      const res = await fetch(`/api/analysis/${currentIndex.value}/ai_snapshot`, { method: 'POST' })
      if (!res.ok) {
        const data = await res.json().catch(() => ({}))
        throw new Error(data.error || `HTTP ${res.status}`)
      }
      const data = await res.json()
      snapshotData.value = data.snapshot
    } catch (e) {
      snapshotError.value = e.message || 'Snapshot failed'
    } finally {
      snapshotLoading.value = false
    }
  }

  function switchIndex(key) {
    currentIndex.value = key
    liveData.value = null
    historicalData.value = null
    snapshotData.value = null
    snapshotError.value = null
    fetchLive(key)
  }

  onMounted(() => {
    fetchLive()
    pollTimer = setInterval(() => fetchLive(), POLL_INTERVAL_MS)
  })

  onUnmounted(() => {
    clearInterval(pollTimer)
  })

  return {
    currentIndex,
    liveData,
    historicalData,
    loading,
    historicalLoading,
    error,
    fetchLive,
    fetchHistorical,
    switchIndex,
    snapshotLoading,
    snapshotData,
    snapshotError,
    fetchAiSnapshot
  }
}
