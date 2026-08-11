import { createSignal, onMount, onCleanup } from 'solid-js'
import toast from 'solid-toast'
import cable from '../cable'
import { dashboardApiHeaders } from '../lib/dashboardApi'

const WS_STALE_AFTER_MS = 3000
const BACKFILL_INTERVAL_MS = 5000

export function usePositions() {
  const [open, setOpen] = createSignal([])
  const [closed, setClosed] = createSignal([])
  const [connected, setConnected] = createSignal(false)
  const [isStale, setIsStale] = createSignal(true)
  const [lastMessageAt, setLastMessageAt] = createSignal(null)
  const [closingPositionId, setClosingPositionId] = createSignal(null)

  let subscription = null
  let staleTimer = null
  let backfillTimer = null

  async function fetchPositions() {
    try {
      const res = await fetch('/api/positions', { headers: dashboardApiHeaders() })
      const data = await res.json()
      setOpen(data.open || [])
      setClosed(data.closed || [])
    } catch (e) {
      console.error('[Positions] fetch failed:', e)
    }
  }

  async function closeOpenPosition(id) {
    if (!id) return
    setClosingPositionId(id)
    try {
      const res = await fetch(`/api/positions/${id}/close`, { method: 'POST', headers: dashboardApiHeaders() })
      const data = await res.json()
      if (res.ok) {
        toast.success(`Position #${id} close requested`)
        setOpen(prev => prev.filter(p => Number(p.id) !== Number(id)))
        fetchPositions()
      } else {
        toast.error(data.error || 'Failed to close position')
      }
    } catch (e) {
      console.error('Failed to close position:', e)
      toast.error('Failed to close position')
    } finally {
      setClosingPositionId(null)
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

  return {
    open,
    closed,
    connected,
    isStale,
    lastMessageAt,
    fetchPositions,
    closeOpenPosition,
    closingPositionId
  }
}
