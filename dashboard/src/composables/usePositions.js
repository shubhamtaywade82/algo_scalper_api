import { ref, onMounted, onUnmounted } from 'vue'
import cable from '../cable'

export function usePositions() {
  const open = ref([])
  const closed = ref([])

  let subscription = null

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

  function applyPnlUpdate(update) {
    const pos = open.value.find(p => p.id === update.id)
    if (!pos) return
    pos.ltp = update.ltp
    pos.pnl = update.pnl
    pos.pnl_pct = update.pnl_pct
    pos.hwm_pnl = update.hwm_pnl
  }

  onMounted(() => {
    fetchPositions()

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
  })

  return { open, closed, fetchPositions }
}
