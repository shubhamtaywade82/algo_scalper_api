import { ref, onMounted, onUnmounted } from 'vue'
import cable from '../cable'

const WS_STALE_AFTER_MS = 3000
const BACKFILL_INTERVAL_MS = 5000

export function usePositions() {
  const open = ref([])
  const closed = ref([])
  const connected = ref(false)
  const isStale = ref(true)
  const lastMessageAt = ref(null)

  let subscription = null
  let staleTimer = null
  let backfillTimer = null

  async function fetchPositions() {
    try {
      const res = await fetch('/api/positions')
      const data = await res.json()
      open.value = data.open || []
      closed.value = data.closed || []
    } catch (e) {
      console.error('[Positions] fetch failed:', e)
    }
  }

  // Replace the whole object at the index so Vue's reactivity picks up the change
  function applyPnlUpdate(update) {
    const idx = open.value.findIndex(p => Number(p.id) === Number(update.id))
    if (idx === -1) return
    open.value[idx] = { ...open.value[idx], ...update }
  }

  function clearStaleTimer() {
    if (staleTimer) {
      clearTimeout(staleTimer)
      staleTimer = null
    }
  }

  function stopBackfill() {
    if (backfillTimer) {
      clearInterval(backfillTimer)
      backfillTimer = null
    }
  }

  function startBackfill() {
    if (backfillTimer) return
    fetchPositions()
    backfillTimer = setInterval(fetchPositions, BACKFILL_INTERVAL_MS)
  }

  function scheduleStaleCheck() {
    clearStaleTimer()
    staleTimer = setTimeout(() => {
      if (!connected.value) return
      isStale.value = true
      startBackfill()
    }, WS_STALE_AFTER_MS)
  }

  function markFresh() {
    lastMessageAt.value = new Date().toISOString()
    isStale.value = false
    stopBackfill()
    scheduleStaleCheck()
  }

  onMounted(() => {
    fetchPositions()

    // WS-first: realtime updates via ActionCable. Polling is fallback only when stale/disconnected.
    subscription = cable.subscriptions.create('PositionsChannel', {
      connected() {
        connected.value = true
        markFresh()
        // Backfill list once on (re)connect for safety.
        fetchPositions()
      },
      disconnected() {
        connected.value = false
        isStale.value = true
        clearStaleTimer()
        startBackfill()
      },
      received(data) {
        if (data.type === 'pnl_update') {
          applyPnlUpdate(data)
          markFresh()
        }
      }
    })
  })

  onUnmounted(() => {
    subscription?.unsubscribe()
    clearStaleTimer()
    stopBackfill()
  })

  return { open, closed, connected, isStale, lastMessageAt, fetchPositions }
}
