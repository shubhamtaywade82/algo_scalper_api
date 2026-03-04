import { ref, onMounted, onUnmounted } from 'vue'
import cable from '../cable'

const POLL_INTERVAL_MS = 5000

export function usePositions() {
  const open = ref([])
  const closed = ref([])

  let subscription = null
  let pollTimer = null

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
    const idx = open.value.findIndex(p => p.id === update.id)
    if (idx === -1) return
    open.value[idx] = { ...open.value[idx], ...update }
  }

  onMounted(() => {
    fetchPositions()

    // Polling — catches position list changes (activations, exits)
    pollTimer = setInterval(fetchPositions, POLL_INTERVAL_MS)

    // ActionCable — sub-second PnL updates for open positions when connected
    subscription = cable.subscriptions.create('PositionsChannel', {
      received(data) {
        if (data.type === 'pnl_update') {
          applyPnlUpdate(data)
        }
      }
    })
  })

  onUnmounted(() => {
    subscription?.unsubscribe()
    clearInterval(pollTimer)
  })

  return { open, closed, fetchPositions }
}
