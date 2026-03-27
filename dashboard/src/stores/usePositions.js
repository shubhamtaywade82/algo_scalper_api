import { createSignal, onMount, onCleanup } from 'solid-js'
import cable from '../cable'

const WS_STALE_AFTER_MS = 3000
const BACKFILL_INTERVAL_MS = 5000

export function usePositions() {
  const [open, setOpen] = createSignal([])
  const [closed, setClosed] = createSignal([])
  const [connected, setConnected] = createSignal(false)
  const [isStale, setIsStale] = createSignal(true)
  const [lastMessageAt, setLastMessageAt] = createSignal(null)

  let subscription = null
  let staleTimer = null
  let backfillTimer = null

  async function fetchPositions() {
    try {
      const res = await fetch('/api/positions')
      const data = await res.json()
      setOpen(data.open || [])
      setClosed(data.closed || [])
    } catch (e) {
      console.error('[Positions] fetch failed:', e)
    }
  }

  function applyPnlUpdate(update) {
    setOpen(prev => {
      const idx = prev.findIndex(p => Number(p.id) === Number(update.id))
      if (idx === -1) return prev
      const next = [...prev]
      next[idx] = { ...next[idx], ...update }
      return next
    })
  }

  function applyPnlStale(staleEvent) {
    setOpen(prev => {
      const idx = prev.findIndex(p => Number(p.id) === Number(staleEvent.id))
      if (idx === -1) return prev
      const next = [...prev]
      next[idx] = { ...next[idx], ltp_stale: true }
      return next
    })
  }

  function clearStaleTimer() {
    if (staleTimer) { clearTimeout(staleTimer); staleTimer = null }
  }

  function stopBackfill() {
    if (backfillTimer) { clearInterval(backfillTimer); backfillTimer = null }
  }

  function startBackfill() {
    if (backfillTimer) return
    fetchPositions()
    backfillTimer = setInterval(fetchPositions, BACKFILL_INTERVAL_MS)
  }

  function scheduleStaleCheck() {
    clearStaleTimer()
    staleTimer = setTimeout(() => {
      if (!connected()) return
      setIsStale(true)
      startBackfill()
    }, WS_STALE_AFTER_MS)
  }

  function markFresh() {
    setLastMessageAt(new Date().toISOString())
    setIsStale(false)
    stopBackfill()
    scheduleStaleCheck()
  }

  onMount(() => {
    fetchPositions()

    subscription = cable.subscriptions.create('PositionsChannel', {
      connected() {
        setConnected(true)
        markFresh()
        fetchPositions()
      },
      disconnected() {
        setConnected(false)
        setIsStale(true)
        clearStaleTimer()
        startBackfill()
      },
      received(data) {
        if (data.type === 'pnl_update') {
          applyPnlUpdate(data)
          markFresh()
        } else if (data.type === 'pnl_stale') {
          applyPnlStale(data)
          markFresh()
        }
      }
    })
  })

  onCleanup(() => {
    subscription?.unsubscribe()
    clearStaleTimer()
    stopBackfill()
  })

  return { open, closed, connected, isStale, lastMessageAt, fetchPositions }
}
