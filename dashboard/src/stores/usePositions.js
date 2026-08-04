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

  // Only carry forward the real-time fields that WS updates provide.
  // Everything else is authoritative from the server.
  function pickLiveFields(pos) {
    const live = {}
    if (pos.ltp != null)       live.ltp       = pos.ltp
    if (pos.pnl != null)       live.pnl       = pos.pnl
    if (pos.pnl_pct != null)   live.pnl_pct   = pos.pnl_pct
    if (pos.hwm_pnl != null)   live.hwm_pnl   = pos.hwm_pnl
    if (pos.ltp_stale != null) live.ltp_stale = pos.ltp_stale
    if (pos.sl_price != null)  live.sl_price  = pos.sl_price
    if (pos.tp_price != null)  live.tp_price  = pos.tp_price
    return live
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
        // ANY incoming data marks fresh and applies update instantly
        console.debug('⚡ [WS:Positions] Update:', data)
        markFresh()
        if (data.type === 'pnl_stale') {
          applyPnlStale(data)
        } else if (data.type === 'keepalive') {
          // markFresh() above resets WS stale timer
        } else if (data.type === 'position_exited') {
          setOpen(prev => prev.filter(p => Number(p.id) !== Number(data.id)))
        } else {
          applyPnlUpdate(data)
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
